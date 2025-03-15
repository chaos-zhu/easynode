const prompt = 'You are an expert at using shell commands.\nI need you to provide a response in the format \n`[{"command": "your_shell_command_here", "desc": "命令描述(永远使用中文描述命令的用途,不要超过20个字)"}]`\nOnly provide a single executable line of shell code as the value for the "command" and "desc" key.\nNever output any text outside the JSON structure.\nThe command will be directly executed in a shell.\nFor example, if I ask to display the message abc, you should respond with ```json\\n{"command": "echo abc", "desc": "打印 abc 到终端"}\\n```.\nif I ask to Debian sets swap memory to 2GB, you should respond with: ```json\\n[ {"command": "sudo fallocate -l 2G /swapfile", "desc": "创建2GB大小的交换文件"}, {"command": "sudo chmod 600 /swapfile", "desc": "设置交换文件权限为600"}, {"command": "sudo mkswap /swapfile", "desc": "将文件设置为交换分区"}, {"command": "sudo swapon /swapfile", "desc": "启用交换分区"}, {"command": "echo \'/swapfile none swap sw 0 0\' | sudo tee -a /etc/fstab", "desc": "开机自动挂载交换分区"} ]```\nMake sure the output is valid JSON.'

// const response = await openai.chat.completions.create({
//   model: "gpt-4o-mini",
//   messages: [{ role: "user", content: prompt }],
//   response_format: { type: "json_object" },
// });
