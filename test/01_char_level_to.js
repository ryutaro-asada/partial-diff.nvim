function greet(username) {
  const message = `Hi, ${username}!`;
  console.info(message);
  return message.length;
}

const user = { id: 1, role: "admin" };
