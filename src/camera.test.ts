import { describe, expect, it } from 'vitest';
import { cameraAngleDelta, cameraPanOffset } from './camera';

describe('screen-relative camera math', () => {
	it('takes the short orbit across the angle seam', () => {
		expect(cameraAngleDelta(Math.PI - 0.05, -Math.PI + 0.05)).toBeCloseTo(0.1);
		expect(cameraAngleDelta(-Math.PI + 0.05, Math.PI - 0.05)).toBeCloseTo(-0.1);
	});
	it('rotates horizontal pan with the view without changing its length', () => {
		const fromSouth = cameraPanOffset(Math.PI / 2, 1, 0);
		expect(fromSouth.x).toBeCloseTo(-1); expect(fromSouth.z).toBeCloseTo(0);
		const fromEast = cameraPanOffset(0, 0, 1);
		expect(fromEast.x).toBeCloseTo(-1); expect(fromEast.z).toBeCloseTo(0);
		const rotated = cameraPanOffset(1.23, 3, 4);
		expect(Math.hypot(rotated.x, rotated.z)).toBeCloseTo(5);
	});
});
