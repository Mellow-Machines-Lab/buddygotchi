// The notes editor: the notes, the command menu and search.
const { commands } = require("./commands");

function createEditor(root) {
  const menu = { open: false, items: commands };
  const search = { open: false, query: "" };
  return {
    root,
    menu,
    search,
    openMenu() {
      menu.open = true;
    },
    closeMenu() {
      menu.open = false;
      root.focus();
    },
    openSearch() {
      search.open = true;
    },
  };
}

module.exports = { createEditor };
