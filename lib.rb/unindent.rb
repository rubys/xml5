Dir['**/*.rb'].each do |file|
  next if file == 'unindent.rb'
  content = open(file) {|fh| fh.read}
  content.gsub!(/^(    )+/) {|s| '  ' * (s.length/4)}
  open(file,'w') {|fh| fh.write content}
end
