// A login page on a pretend screen: the welcome text shows a moment after
// you log in, as it does once the server answers.
const shown = [];

const screen = {
  text: () => shown.join("\n"),
  // Waits for `text` to show, up to a second.
  findByText: (text) =>
    new Promise((resolve, reject) => {
      const start = Date.now();
      const look = () => {
        if (shown.some((line) => line.includes(text))) return resolve(text);
        if (Date.now() - start > 1000) return reject(new Error(`"${text}" never showed`));
        setTimeout(look, 10);
      };
      look();
    }),
};

function login(name) {
  setTimeout(() => shown.push(`Welcome, ${name}`), 150);
}

module.exports = { screen, login };
