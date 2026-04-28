file = "/root/.vscode-remote/data/User/workspaceStorage/-506f54d9/GitHub.copilot-chat/chat-session-resources/2b6bb004-8e13-4752-9a81-8f2f999c93dd/call_MHwzdlF1R0N3Z3VBSTZlemdvajg__vscode-1777000479437/content.txt"
content = File.read(file)
summary = content.scan(/\d+ runs, \d+ assertions, \d+ failures, \d+ errors, \d+ skips/)
puts summary
