require 'erb'
require 'ripper'

code = File.read('app/views/home/index.html.erb')
# Rails uses a specialized ERB processor, but for simple syntax check we can do this:
# We need to handle block syntax which ERB.new(..).src doesn't handle natively for <%= ... do %>
# So we replace <%= ... do %> with <% ... do %> just for syntax checking blocks
modified_code = code.gsub(/<%= (.* do.*) %>/, '<% \1 %>')
erb_src = ERB.new(modified_code, trim_mode: '-').src
syntax_errors = Ripper.sexp(erb_src).nil?

if syntax_errors
  puts "Syntax Error detected"
  system("ruby -c << 'SRC'\n#{erb_src}\nSRC")
else
  puts "Syntax OK"
end
