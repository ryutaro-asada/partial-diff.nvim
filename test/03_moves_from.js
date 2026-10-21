function validateInput(value) {
  if (value == null) {
    throw new Error("value is required");
  }
  if (typeof value !== "string") {
    throw new Error("value must be a string");
  }
  return value.trim();
}

function formatOutput(value) {
  return value.toUpperCase();
}

function main(value) {
  const clean = validateInput(value);
  return formatOutput(clean);
}
