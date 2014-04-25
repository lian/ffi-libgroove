require "bundler/setup"
require "eventmachine"

ENV['SDL_AUDIODRIVER'] = 'dummy'
$:.unshift( File.expand_path("../../lib", __FILE__) )
require 'ffi-libgroove'
require 'ffi-libgroove/stream_encoder'


Groove.init

playlist = Groove::Playlist.new
playlist.volume = 0.8
#playlist.pause

ARGV.each{|i|
 next unless File.file?(i)
 file = Groove.file_open(i)
 playlist.insert(file, 1.0)
}

player = Groove::Player.new
player.attach(playlist)

#encoder = Groove::Encoder.default_encoder
encoder = Groove::StreamEncoder.new(player)
encoder.attach(playlist)


class Keyboard < EM::Connection
  include EM::Protocols::LineText2
  def initialize(cb); @cb = cb; end
  def receive_line(line)
    puts "<< #{line}"
    cmd, *args = line.split(" ")
    @cb.call(cmd, args)
  end
  def self.open(&blk); EM.open_keyboard(self, blk); end
end


EM.run{
  stream_server, flush_timer = Groove::StreamConnection.start_server("127.0.0.1", 4000, encoder)

  EM.add_periodic_timer(2.0){
    p [:status, playlist.get_position, encoder.get_position]
  }

  input = Keyboard.open{|cmd, args|
    case cmd
    when "q", "quit"; EM.stop
    when "play"; playlist.play
    when "pause"; playlist.pause
    when "add"
      if filename = args.first
        if File.file?(filename)
           file = Groove.file_open(filename)
           playlist.insert(file, 1.0)
        elsif File.directory?(filename)
           Dir["#{filename}/*.mp3"].each{|filename|
             file = Groove.file_open(filename)
             playlist.insert(file, 1.0)
           }
        end
      end
    when "list"
      playlist.each_item{|item, filename, gain, file, current_item|
        p [item, filename, gain, file, current_item]
      }
    when "clear"
      playlist.remove_items
    when "next"; playlist.playlist_seek(:next)
    when "prev"; playlist.playlist_seek(:prev)
    end
  }

  player_event_loop = EM.add_periodic_timer(1.0){
    event = player.get_event(blocking=false)
    #p [:event, event]
    case event
    when :end;
    when :buffer_underun; # skip
    #when :no_event; # skip
    #when :nowplaying
    when :nowplaying, :no_event
      item, seconds = player.get_position
      #item_, seconds_ = playlist.get_position
      #p [item == item, item, seconds, seconds_]
      if item and !item.null?
        pl_item = Groove::PlaylistItem.new(item)
        artist_tag = Groove.groove_file_metadata_get(pl_item[:file], "artist", nil, 0)
        title_tag  = Groove.groove_file_metadata_get(pl_item[:file], "title", nil, 0)
   
        if event == :nowplaying
          if !artist_tag.null? and !title_tag.null?
            p "now playing: %s - %s  pos=%f" % [ Groove.groove_tag_value(artist_tag), Groove.groove_tag_value(title_tag), seconds ]
          else
            file = Groove::GrooveFile.new(pl_item[:file])
            p "now playing: %s" % [ file[:filename] ]
          end
        end
      else
        p :done; #exit
      end
    end
  }

}

p :cleanup
player.detach
player.destroy
encoder.detach
encoder.destroy
playlist.destroy
