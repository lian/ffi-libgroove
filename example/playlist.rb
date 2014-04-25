$:.unshift( File.expand_path("../../lib", __FILE__) )
require 'ffi-libgroove'

Groove.init

p pl = Groove::Playlist.new
p pl.count
pl.volume = 0.8

ARGV.each{|i|
 next unless File.file?(i)
 file = Groove.file_open(i)
 pl.insert(file, 1.0)
}

p player = Groove::Player.new
p player.attach(pl)

loop{
  event = player.get_event(blocking=false)
  p [:event, event]
  case event
  when :end; break
  when :buffer_underun; # skip
  #when :no_event; # skip
  #when :nowplaying
  when :nowplaying, :no_event
    item, seconds = player.get_position
    if item
      next if item.null?

      pl_item = Groove::PlaylistItem.new(item)
      artist_tag = Groove.groove_file_metadata_get(pl_item[:file], "artist", nil, 0)
      title_tag  = Groove.groove_file_metadata_get(pl_item[:file], "title", nil, 0)
 
      if !artist_tag.null? and !title_tag.null?
        p "now playing: %s - %s  pos=%f" % [ Groove.groove_tag_value(artist_tag), Groove.groove_tag_value(title_tag), seconds ]
      else
        file = Groove::GrooveFile.new(pl_item[:file])
        p "now playing: %s" % [ file[:filename] ]
      end
    else
      p :done; exit
    end
  end
  sleep(1.0)
}
