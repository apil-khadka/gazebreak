import { defineConfig } from 'vite';
import { fileURLToPath } from 'node:url';

export default defineConfig({
  base: process.env.PAGES_BASE_PATH || '/gazebreak/',
  build: {
    rolldownOptions: {
      input: Object.fromEntries(['index', 'guide', 'releases'].map(name => [
        name, fileURLToPath(new URL(`./${name}.html`, import.meta.url)),
      ])),
    },
  },
});
