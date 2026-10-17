import { mkdir, writeFile, readFile } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const root = fileURLToPath(new URL('../', import.meta.url));
const manifestPath = path.join(root, 'public/actors/source-manifest.json');
if (process.argv.includes('--verify')) {
	const manifest = JSON.parse(await readFile(manifestPath, 'utf8'));
	for (const source of manifest.sources) {
		const bytes = await readFile(path.join(root, source.localPath));
		const sha256 = createHash('sha256').update(bytes).digest('hex');
		if (sha256 !== source.sha256 || bytes.length !== source.bytes) throw new Error(`Integrity failure: ${source.localPath}`);
	}
	console.log(`Verified ${manifest.sources.length} downloaded source files; ${manifest.totalBytes} bytes`);
	process.exit(0);
}
const sources = [];
const modelCommit = '8a3857c250a5c271429aefa82c660ff35803166e';
const spineCommit = '8b4844bd4b193ba9e54487ed397a777993cbad56';
const models = [
	['amiya', 'models/002_amiya', 'build_char_002_amiya'],
	['hoshiguma', 'models/136_hsguma', 'build_char_136_hsguma'],
	['ansel', 'models/212_ansel', 'build_char_212_ansel'],
	['melee', 'models_enemies/1002_nsabr', 'enemy_1002_nsabr'],
	['ranged', 'models_enemies/1003_ncbow', 'enemy_1003_ncbow'],
];
let totalBytes = 0;
async function retrieve(repository, commit, remotePath, localPath) {
	const url = `https://raw.githubusercontent.com/${repository}/${commit}/${remotePath}`;
	let bytes;
	for (let attempt = 0; attempt < 5; attempt++) {
		try {
			const response = await fetch(url, { signal: AbortSignal.timeout(25000) });
			if (!response.ok) throw new Error(`${response.status}: ${url}`);
			bytes = Buffer.from(await response.arrayBuffer());
			break;
		} catch (error) {
			if (attempt === 4) throw error;
			await new Promise(resolve => setTimeout(resolve, 1000 * (attempt + 1)));
		}
	}
	totalBytes += bytes.length;
	if (totalBytes > 30 * 1024 * 1024) throw new Error('Actor asset download exceeded 30 MiB');
	const destination = path.join(root, localPath);
	await mkdir(path.dirname(destination), { recursive: true });
	await writeFile(destination, bytes);
	sources.push({ repository, commit, remotePath, localPath, url, bytes: bytes.length,
		sha256: createHash('sha256').update(bytes).digest('hex'), retrievedAt: new Date().toISOString() });
	console.log(`${localPath}: ${bytes.length} bytes`);
}
for (const [role, folder, name] of models) {
	for (const extension of ['atlas', 'png', 'skel']) {
		await retrieve('isHarryh/Ark-Models', modelCommit, `${folder}/${name}.${extension}`, `public/actors/${role}/${name}.${extension}`);
	}
}
await retrieve('EsotericSoftware/spine-runtimes', spineCommit, 'spine-ts/build/spine-webgl.js', 'public/vendor/spine-webgl-3.8.js');
await retrieve('EsotericSoftware/spine-runtimes', spineCommit, 'spine-ts/LICENSE', 'public/vendor/SPINE_RUNTIME_LICENSE.txt');
await writeFile(manifestPath, JSON.stringify({ totalBytes, sources }, null, 2));
console.log(`Total: ${(totalBytes / 1024 / 1024).toFixed(2)} MiB`);
