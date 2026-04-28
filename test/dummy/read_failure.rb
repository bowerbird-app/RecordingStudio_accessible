content = File.read("/root/.vscode-remote/data/User/workspaceStorage/-506f54d9/GitHub.copilot-chat/chat-session-resources/a78c98f1-5dd3-4d2a-8cbb-ee589104f311/call_MHxWWjNDSFFuQ05XeHl2ak5xS2g__vscode-1777000479518/content.txt")
lines = content.split("\n")
failure_line_index = lines.find_index { |l| l.include?("Failure:") }
if failure_line_index
  puts lines[failure_line_index, 10].join("\n")
else
  puts "No failure found"
end
