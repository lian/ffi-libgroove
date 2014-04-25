$:.unshift( File.expand_path("../../lib", __FILE__) )
require 'ffi-libgroove'

Groove.init

playlist = Groove::Playlist.new

ARGV.each{|i|
 next unless File.file?(i)
 file = Groove.file_open(i)
 playlist.insert(file, 1.0)
}

encoder = Groove::Encoder.default_encoder
encoder.attach(playlist)

loop{
  if true
    state, buf = encoder.get_buffer(blocking=false)
    case state
    when :end; break
    when :none; # skip
    when :buffer
      p [:new_data, buf.bytesize]
    end
    sleep 0.1
  else
    buffers, len = encoder.read(min=45975)
    p [:new_data, len]
    sleep(1.0)
  end
}

encoder.detach
