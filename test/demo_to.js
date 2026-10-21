// README demo recreation — "after" version
function applyDiscount(total, rate) {
  return total - total * rate;
}

function calculateTotal(items) {
  var total = 0;
  for (var i = 0; i < items.length; i++) {
    total = total + items[i].price;
  }
  return total;
}

function checkout(cart) {
  const total = calculateTotal(cart.items);
  const final = applyDiscount(total, cart.discount);
  console.info(`Total: ${final}`);
  return final;
}
