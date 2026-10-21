function process(items) {
if (items.length === 0) {
return [];
}
return items.map(function (item) {
return item * 2;
});
}
