require 'ffi'

module Groove
  extend FFI::Library
  ffi_lib 'groove'
  GROOVE_LOG_INFO = 32

  # init functions
  attach_function :groove_init, [], :void
  attach_function :groove_set_logging, [:uint], :void
  attach_function :groove_buffer_unref, [:pointer], :void

  # playlist functions
  attach_function :groove_playlist_create, [], :pointer
  attach_function :groove_playlist_destroy, [:pointer], :void
  attach_function :groove_playlist_play, [:pointer], :void
  attach_function :groove_playlist_pause, [:pointer], :void
  attach_function :groove_playlist_seek, [:pointer, :pointer, :double], :void
  attach_function :groove_playlist_insert, [:pointer, :pointer, :double, :pointer], :pointer
  attach_function :groove_playlist_remove, [:pointer, :pointer], :void
  attach_function :groove_playlist_position, [:pointer, :pointer, :pointer], :void
  attach_function :groove_playlist_playing, [:pointer], :int
  attach_function :groove_playlist_clear, [:pointer], :void
  attach_function :groove_playlist_count, [:pointer], :int
  attach_function :groove_playlist_set_gain, [:pointer, :pointer, :double], :void
  attach_function :groove_playlist_set_volume, [:pointer, :double], :void

  # encoder functions
  attach_function :groove_encoder_create, [], :pointer
  attach_function :groove_encoder_destroy, [:pointer], :void
  attach_function :groove_encoder_attach, [:pointer, :pointer], :int
  attach_function :groove_encoder_detach, [:pointer], :void
  attach_function :groove_encoder_buffer_get, [:pointer, :pointer, :int], :int
  attach_function :groove_encoder_buffer_peek, [:pointer, :int], :int
  attach_function :groove_encoder_position, [:pointer, :pointer, :pointer], :int

  # file functions
  attach_function :groove_file_open, [:string], :pointer
  attach_function :groove_file_close, [:pointer], :void
  attach_function :groove_file_metadata_get, [:pointer, :string, :pointer, :int], :pointer
  attach_function :groove_tag_value, [:pointer], :string


  ffi_lib 'grooveplayer'
  # player functions
  attach_function :groove_device_count, [], :int
  attach_function :groove_device_name, [:int], :string
  attach_function :groove_player_create, [], :pointer
  attach_function :groove_player_destroy, [:pointer], :void
  attach_function :groove_player_attach, [:pointer, :pointer], :int
  attach_function :groove_player_detach, [:pointer], :int
  attach_function :groove_player_position, [:pointer, :pointer, :pointer], :int
  attach_function :groove_player_event_get, [:pointer, :pointer, :int], :int
  attach_function :groove_player_event_peek, [:pointer, :int], :int

  class Player
    attr_reader :player
    def initialize
      @player = Groove.groove_player_create
      raise "Error creating player." if @player.null?
    end

    def destroy
      Groove.groove_player_destroy(@player)
    end

    def attach(playlist)
      pl = if playlist.is_a?(Groove::Playlist)
             @playlist = playlist
             playlist.pl
           else
             playlist
           end
      (Groove.groove_player_attach(@player, pl) == 0) ? true : false
    end

    def detach
      @playlist = nil
      (Groove.groove_player_detach(@player) == 0) ? true : false
    end

    def get_position
      item, seconds = FFI::MemoryPointer.new(:pointer), FFI::MemoryPointer.new(:double)
      Groove.groove_player_position(@player, item, seconds)
      if item.null? #or item.read_pointer.null?
        [nil, 0]
      else
        [item.read_pointer, seconds.read_double]
      end
    end

    Events = { 0 => :nowplaying, 1 => :buffer_underun}
    def get_event(blocking=false)
      event = FFI::MemoryPointer.new(:uint)
      ret = Groove.groove_player_event_get(@player, event, blocking ? 1 : 0)
      case ret
      when 1; Events[event.read_uint]
      when 0; :no_event
      else; :end
      end
    end

    def peek_event(blocking=false)
      Groove.groove_player_event_peek(@player, blocking ? 1 : 0) == 1
    end

    def self.devices
      count = Groove.groove_device_count
      count.times.map{|idx|
        Groove.groove_device_name(idx)
      }
    end
  end

  class Playlist
    attr_reader :pl
    def initialize
      @pl = Groove.groove_playlist_create
      raise "Error creating playlist." if @pl.null?
    end
    def volume=(value)
      Groove.groove_playlist_set_volume(@pl, value.to_f)
    end
    def gain=(value)
      Groove.groove_playlist_set_gain(@pl, value.to_f)
    end
    def destroy
      remove_items
      if @player
        @player.detach
        @player.destroy
      end
      Groove.groove_playlist_destroy(@pl)
    end
    def play
      Groove.groove_playlist_play(@pl)
    end
    def pause
      Groove.groove_playlist_pause(@pl)
    end
    def playing?
      (Groove.groove_playlist_playing(@pl) == 1) ? true : false
    end
    def seek(item, seconds)
      Groove.groove_playlist_seek(@pl, item, seconds)
    end

    def playlist_seek(direction=nil)
      a, b = case direction
             when :next; [:next, :head]
             when :prev; [:prev, :tail]
             end
      item, _ = get_position
      if item and !item.null?
        item_s = PlaylistItem.new(item)
        if !item_s[a].null?
          seek(item_s[a], 0.0)
        else
          seek(GroovePlaylist.new(@pl)[b], 0.0)
        end
      end
    end

    def clear
      Groove.groove_playlist_clear(@pl)
    end
    def count
      Groove.groove_playlist_count(@pl)
    end
    def get_position
      item, seconds = FFI::MemoryPointer.new(:pointer), FFI::MemoryPointer.new(:double)
      Groove.groove_playlist_position(@pl, item, seconds)
      if item.null?
        [nil, 0]
      else
        [item.read_pointer, seconds.read_double]
      end
    end

    def insert(file, gain=1.0, next_item=nil)
      item = Groove.groove_playlist_insert(@pl, file, gain, next_item)
    end

    def remove_item(item)
      Groove.groove_playlist_remove(@pl, item)
    end

    def remove_items
      each_item{|item, filename, gain, file|
        remove_item(item)
        Groove.groove_file_close(file)
      }
    end

    def each_item(&blk)
      cur_item, _ = get_position
      if cur_item.nil? or cur_item.null?
        cur_item = nil
      end

      item = GroovePlaylist.new(@pl)[:head]
      until item.null?
        item_s = PlaylistItem.new(item)
        file = GrooveFile.new(item_s[:file])
        next_item = item_s[:next]
        blk.call(item, file[:filename], item_s[:gain], item_s[:file], cur_item == item)
        item = next_item
      end
    end

  end

  class Encoder
    def initialize
      @encoder = Groove.groove_encoder_create
      @encoder_s = Groove::GrooveEncoder.new(@encoder)
    end

    def bit_rate=(value=256); @encoder_s[:bit_rate] = value * 1000; end
    def format=(value); @encoder_s[:format_short_name] = FFI::MemoryPointer.from_string(value); end
    def codec=(value); @encoder_s[:codec_short_name] = FFI::MemoryPointer.from_string(value); end
    def filename=(value); @encoder_s[:filename] = FFI::MemoryPointer.from_string(value); end
    def mine_type=(value); @encoder_s[:mine_type] = FFI::MemoryPointer.from_string(value); end

    def attach(playlist)
      pl = if playlist.is_a?(Groove::Playlist)
             @playlist = playlist
             playlist.pl
           else
             playlist
           end
      if Groove.groove_encoder_attach(@encoder, pl) >= 0
        true
      else
        raise "error attaching encoder"
      end
    end

    def detach
      Groove.groove_encoder_detach(@encoder)
    end

    def destroy
      Groove.groove_encoder_destroy(@encoder)
    end

    def get_position
      item, seconds = FFI::MemoryPointer.new(:pointer), FFI::MemoryPointer.new(:double)
      Groove.groove_encoder_position(@encoder, item, seconds)
      if item.null?
        [nil, 0]
      else
        [item.read_pointer, seconds.read_double]
      end
    end

    def get_buffer(blocking=false)
      data = nil
      @buf ||= FFI::MemoryPointer.new(:pointer)

      state = Groove.groove_encoder_buffer_get(@encoder, @buf, 0)
      case state
      when Groove::GROOVE_BUFFER_END
        [:end, nil, nil, nil]
      when Groove::GROOVE_BUFFER_NO
        [:none, nil, nil, nil]
      when Groove::GROOVE_BUFFER_YES
        buffer = Groove::GrooveBuffer.new(@buf.read_pointer)
        type = buffer[:item].null? ? :header : :buffer
        item, pos = buffer[:item], buffer[:pos]
        data = buffer[:data].read_pointer.read_string(buffer[:size])
        Groove.groove_buffer_unref(@buf)
        [type, data, item, pos]
      end
    end

    def read(size)
      buffers, buffer_length = "".force_encoding('binary'), 0
      until buffer_length >= size
        state, buf = get_buffer(block=false)
        break if state == :end
        if state == :buffer
          buffers << buf
          buffer_length += buf.bytesize
        end
      end
      [buffers, buffer_length]
    end

    def self.default_encoder
      encoder          = new
      encoder.bit_rate = 256
      encoder.format   = "mp3"
      encoder.codec    = "mp3"
      encoder
    end
  end

  def self.files; @files ||= {}; end

  def self.file_open(filename)
    return nil unless File.file?(filename)
    path = File.expand_path(filename)
    file = Groove.groove_file_open(path)
    raise "failed to open %s" % [path] if file.null?
    #files[path] = file
    file
  end


  def self.init
    groove_init
    groove_set_logging(GROOVE_LOG_INFO)
  end

  class GrooveFile < FFI::Struct
    layout(:dirty, :int, :filename, :string)
  end

  class PlaylistItem < FFI::Struct
    layout(:prev, :pointer, :file, :pointer, :gain, :double, :next, :pointer)
  end

  class GrooveAudioFormat < FFI::Struct
    layout(
      :sample_rate, :int,
      :channel_layout, :uint64,
      :sample_fmt, :uint,
    )
  end

  class GrooveEncoder < FFI::Struct
    layout(
      :target_audio_format, GrooveAudioFormat,
      :bit_rate, :int,
      #:format_short_name, :string,
      :format_short_name, :pointer,
      #:codec_short_name, :string,
      :codec_short_name, :pointer,
      #:filename, :string,
      :filename, :pointer,
      #:mine_type, :string,
      :mine_type, :pointer,
      :sink_buffer_size, :int,
      :encoded_buffer_size, :int,
      :playlist, :pointer,
      :actual_audio_format, GrooveAudioFormat
    )
  end

  class GroovePlaylist < FFI::Struct
    layout(:head, :pointer, :tail, :pointer, :volume, :double)
  end

  GROOVE_BUFFER_NO  = 0
  GROOVE_BUFFER_YES = 1
  GROOVE_BUFFER_END = 2

  class GrooveBuffer < FFI::Struct
    layout(
      :data, :pointer,
      :format, GrooveAudioFormat,
      :frame_count, :int,
      :item, :pointer,
      :pos, :double,
      :size, :int,
    )
  end
end
