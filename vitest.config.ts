import { defineConfig } from 'vitest/config';

export default defineConfig({
	cacheDir: '.qa/cache/vitest',
	test: { include: ['src/**/*.test.ts'] },
});
