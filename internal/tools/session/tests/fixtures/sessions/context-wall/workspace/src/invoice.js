// Invoice totals, in cents so they add up exactly.

// What the lines cost before anything comes off: each line's price times
// its quantity.
function subtotal(lines) {
  return lines.reduce((sum, line) => sum + line.price * line.qty, 0);
}

// What the customer pays.
function total(invoice) {
  return subtotal(invoice.lines);
}

module.exports = { subtotal, total };
