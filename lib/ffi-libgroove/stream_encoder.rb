module Groove

  class StreamEncoder < Encoder
    attr_reader :player, :playlist, :chan

    def initialize(player)
      super()
      self.bit_rate = 256
      self.format   = "mp3"
      self.codec    = "mp3"

      @player = player # for seconds_into_future timing (workaround)
      @chan = EM::Channel.new if defined?(::EM)

      @instant_buffer_bytes = 220 * 1024;
      @expect_headers = true
      @header_buffers = []
      @new_header_buffers = []
      @recent_buffers = []
      @recent_buffers_bytecount = 0
    end

    def clear_encoded_buffer
      @recent_buffers = []
      @recent_buffers_bytecount = 0
    end

    attr_reader :header_buffers, :recent_buffers

    def seconds_into_future
      pl_item, pl_pos = @player.get_position # (on player)
      en_item, en_pos = get_position # (on encoder)
      if pl_item == en_item
        en_pos - pl_pos
      else
        pl_pos
      end
    end

    def flush_encoded
      return if !@playlist.playing?

      loop{
        buffered_seconds = seconds_into_future
        #p [:buffered_seconds, buffered_seconds]
        break if (buffered_seconds > 0.5) and (@recent_buffers_bytecount >= @instant_buffer_bytes)
        state, buf, item, pos = get_buffer
        case state
        when :buffer
          if @expect_headers
            p "encoder: got first non-header"
            @header_buffers = @new_header_buffers.map{|i| i.dup }
            @new_header_buffers = []
            @expect_headers = false
          end

          @recent_buffers << buf
          @recent_buffers_bytecount += buf.bytesize
          while (@recent_buffers.size > 0) and ((@recent_buffers_bytecount - @recent_buffers[0].bytesize) >= @instant_buffer_bytes)
            @recent_buffers_bytecount -= @recent_buffers.shift.bytesize
          end

          # push out to open streamers
          @chan.push(buf) if @chan

        when :header
          if @expect_headers
            @new_header_buffers << buf
          else
            # ignore footer
          end
        when :none
          break
        when :end
          @expect_headers = true
        end

      }
    end
  end

  if defined?(::EM)
    class StreamConnection < EM::Connection
      def initialize(encoder)
        @stream_encoder = encoder
        send_headers
        send_stream_start
        @stream_encoder.chan.subscribe(&method(:on_buffer))
      end

      def send_stream_start
        header_count, data_count = 0, 0
        @stream_encoder.header_buffers.each{|buf| header_count += buf.bytesize; chunk(buf) }
        @stream_encoder.recent_buffers.each{|buf| data_count += buf.bytesize; chunk(buf) }
        p ["stream sent #{header_count} bytes of headers and #{data_count} bytes of unthrottled data"]
      end

      def on_buffer(data)
        chunk(data)
      end

      def send_headers
        headers = ["HTTP/1.1 200 OK",
                   "Content-Type: audio/mpeg",
                   "Cache-Control: no-cache, no-store, must-revalidate",
                   "Pragma: no-cache",
                   "Expires: 0",
                   "Connection: keep-alive",
                   "Transfer-Encoding: chunked"
                   ].join("\r\n") + "\r\n\r\n"
        send_data headers
      end

      def chunk(data)
        send_data "#{data.bytesize.to_s(16)}\r\n#{data}\r\n"
      end

      def stream_close
        send_data("0\r\n\r\n")
      end

      def receive_data(data)
        # ignore
      end

      def self.start_server(host, port, encoder)
        server = EM.start_server(host, port, self, encoder)
        flush_timer = EM.add_periodic_timer(0.5){ encoder.flush_encoded }
        [server, flush_timer]
      end

    end
  end

end
