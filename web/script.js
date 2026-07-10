const screenshotImages = document.querySelectorAll('[data-dark-src][data-light-src]');
const colorScheme = window.matchMedia('(prefers-color-scheme: dark)');

function applyScreenshotTheme(theme) {
  screenshotImages.forEach((image) => {
    image.dataset.displayedTheme = theme;
    image.src = image.dataset[`${theme}Src`];
  });
}

screenshotImages.forEach((image) => {
  image.addEventListener('error', () => {
    if (image.dataset.displayedTheme === 'light') {
      image.dataset.displayedTheme = 'dark';
      image.src = image.dataset.darkSrc;
    }
  });
});

applyScreenshotTheme(colorScheme.matches ? 'dark' : 'light');

colorScheme.addEventListener('change', (event) => {
  applyScreenshotTheme(event.matches ? 'dark' : 'light');
});
