<<<<<<< FROM
function greet(name) {
  const message = "Hello, " + name;
  console.log(message);
  return message.length;
}

const user = { id: 1, role: "guest" };
=======
function greet(username) {
  const message = `Hi, ${username}!`;
  console.info(message);
  return message.length;
}

const user = { id: 1, role: "admin" };
>>>>>>> TO
