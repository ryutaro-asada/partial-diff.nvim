// README demo recreation — "before" version
function calculateTotal(items) {
  var total = 0;
  for (var i = 0; i < items.length; i++) {
    total = total + items[i].price;
  }
  return total;
}

function applyDiscount(total, rate) {
  return total - total * rate;
}

function checkout(cart) {
  var total = calculateTotal(cart.items);
  var final = applyDiscount(total, cart.discount);
  console.log("Total: " + final);
  return final;
}
