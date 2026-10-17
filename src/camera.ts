import { ArcRotateCamera } from '@babylonjs/core/Cameras/arcRotateCamera';
import type { Scene } from '@babylonjs/core/scene';
import { Vector3 } from '@babylonjs/core/Maths/math.vector';
import type { Point } from './shared';

export type CameraMode = 'explore' | 'battle' | 'overview';
export type CameraFocus = Point & { y?: number };
export interface CameraPreset {
	alpha: number;
	beta: number;
	radius: number;
	target: CameraFocus;
}
export interface CameraElevationBounds {
	minY?: number;
	maxY?: number;
	minRadius?: number;
	maxRadius?: number;
}

const clamp = (value: number, min: number, max: number): number => Math.max(min, Math.min(max, value));
const eased = (rate: number, dt: number): number => 1 - Math.exp(-rate * dt);
/** Signed shortest difference, preserving continuity when an orbit crosses ±π. */
export const cameraAngleDelta = (from: number, to: number): number => Math.atan2(Math.sin(to - from), Math.cos(to - from));
/** Horizontal world offset for screen-right and screen-forward camera movement. */
export const cameraPanOffset = (alpha: number, right: number, forward: number): Point => ({
	x: -Math.sin(alpha) * right - Math.cos(alpha) * forward,
	z: Math.cos(alpha) * right - Math.sin(alpha) * forward,
});

/** Browser-native orbit/pan controls. A desired target belongs to the user until
 * follow(true) or focus() is explicitly requested; update() never snaps it back.
 * The camera intentionally does not attach Babylon's default keyboard/pointers,
 * which would compete with tactical clicks and the damped target below.
 */
export class CameraController {
	readonly camera: ArcRotateCamera;
	private abort = new AbortController();
	private pressed = new Set<string>();
	private drag: { pointer: number; button: number; x: number; y: number } | null = null;
	private desiredTarget = new Vector3(0, 0.8, 12);
	private desiredAlpha = Math.PI / 2 + 0.32;
	private desiredBeta = 0.74;
	private desiredRadius = 30;
	private following = true;
	private latestFocus: CameraFocus = { x: 0, z: 12, y: 0.8 };
	private mode: CameraMode = 'explore';
	private minX = -30;
	private maxX = 30;
	private minZ = -40;
	private maxZ = 40;
	private minY = 0;
	private maxY = 24;
	private minRadius = 6;
	private maxRadius = 115;
	private velocity = { right: 0, forward: 0 };
	private disposed = false;

	constructor(scene: Scene, private canvas: HTMLCanvasElement) {
		this.camera = new ArcRotateCamera('hotel-camera', this.desiredAlpha, this.desiredBeta, this.desiredRadius, this.desiredTarget.clone(), scene);
		this.camera.inputs.clear();
		this.camera.inertia = 0;
		this.camera.lowerBetaLimit = 0.25;
		this.camera.upperBetaLimit = 1.32;
		this.camera.lowerRadiusLimit = this.minRadius;
		this.camera.upperRadiusLimit = this.maxRadius;
		this.camera.minZ = 0.1;
		this.camera.maxZ = 1600;
		this.camera.allowUpsideDown = false;
		if (canvas.tabIndex < 0) canvas.tabIndex = 0;
		const signal = this.abort.signal;
		canvas.addEventListener('contextmenu', event => event.preventDefault(), { signal });
		canvas.addEventListener('pointerdown', this.pointerDown, { signal });
		canvas.addEventListener('pointermove', this.pointerMove, { signal });
		canvas.addEventListener('pointerup', this.pointerUp, { signal });
		canvas.addEventListener('pointercancel', this.pointerUp, { signal });
		canvas.addEventListener('lostpointercapture', this.pointerUp, { signal });
		canvas.addEventListener('wheel', this.wheel, { passive: false, signal });
		window.addEventListener('keydown', this.keyDown, { signal });
		window.addEventListener('keyup', this.keyUp, { signal });
		window.addEventListener('blur', this.clearInput, { signal });
		document.addEventListener('visibilitychange', this.visibilityChanged, { signal });
	}

	/** Set actual scene extents. Optional elevation permits multi-storey maps. */
	setBounds(minX: number, maxX: number, minZ: number, maxZ: number, elevation: CameraElevationBounds = {}): void {
		if (![minX, maxX, minZ, maxZ].every(Number.isFinite) || minX >= maxX || minZ >= maxZ) throw new Error('Camera bounds must be finite, ordered scene extents');
		this.minX = minX; this.maxX = maxX; this.minZ = minZ; this.maxZ = maxZ;
		this.minY = elevation.minY ?? 0;
		this.maxY = Math.max(this.minY, elevation.maxY ?? Math.max(24, Math.max(maxX - minX, maxZ - minZ) * 0.2));
		this.minRadius = Math.max(1, elevation.minRadius ?? 6);
		this.maxRadius = Math.max(this.minRadius + 1, elevation.maxRadius ?? Math.max(30, Math.hypot(maxX - minX, maxZ - minZ) * 1.15));
		this.camera.lowerRadiusLimit = this.minRadius;
		this.camera.upperRadiusLimit = this.maxRadius;
		this.camera.maxZ = Math.max(500, this.maxRadius * 8);
		this.clampTarget();
		this.desiredRadius = clamp(this.desiredRadius, this.minRadius, this.maxRadius);
		if (this.mode === 'overview') this.frameOverview();
	}

	/** Focus the point and resume following the current actor supplied to update. */
	focus(point: CameraFocus, immediate = false): void {
		this.latestFocus = { ...point };
		this.desiredTarget.set(point.x, point.y ?? 0.8, point.z);
		this.clampTarget();
		this.following = true;
		this.velocity.right = this.velocity.forward = 0;
		if (immediate) this.camera.setTarget(this.desiredTarget.clone(), false, false, true);
	}

	follow(enabled: boolean): void {
		this.following = enabled;
		if (enabled) {
			this.velocity.right = this.velocity.forward = 0;
			this.desiredTarget.set(this.latestFocus.x, this.latestFocus.y ?? 0.8, this.latestFocus.z);
			this.clampTarget();
		}
	}

	get isFollowing(): boolean { return this.following; }

	setMode(mode: CameraMode): void {
		if (this.mode === mode) return;
		this.mode = mode;
		if (mode === 'overview') { this.frameOverview(); return; }
		this.desiredBeta = mode === 'battle' ? 0.7 : 0.8;
		this.desiredRadius = clamp(mode === 'battle' ? 22 : 16, this.minRadius, this.maxRadius);
		this.follow(true);
	}

	/** Radians and world units, compatible with extracted Arknights map cameras. */
	applyPreset(preset: CameraPreset, immediate = false): void {
		if (![preset.alpha, preset.beta, preset.radius, preset.target.x, preset.target.z, preset.target.y ?? 0.8].every(Number.isFinite)) throw new Error('Camera preset contains non-finite values');
		this.desiredAlpha = preset.alpha;
		this.desiredBeta = clamp(preset.beta, this.camera.lowerBetaLimit!, this.camera.upperBetaLimit!);
		this.desiredRadius = clamp(preset.radius, this.minRadius, this.maxRadius);
		this.desiredTarget.set(preset.target.x, preset.target.y ?? 0.8, preset.target.z);
		this.clampTarget(); this.following = false;
		this.velocity.right = this.velocity.forward = 0;
		if (immediate) {
			this.camera.alpha = this.desiredAlpha; this.camera.beta = this.desiredBeta; this.camera.radius = this.desiredRadius;
			this.camera.setTarget(this.desiredTarget.clone(), false, false, true);
		}
	}

	update(dt: number, focusPoint: CameraFocus): void {
		if (this.disposed) return;
		const delta = clamp(dt, 0, 0.1);
		this.latestFocus = { ...focusPoint };
		let right = Number(this.pressed.has('KeyD') || this.pressed.has('ArrowRight')) - Number(this.pressed.has('KeyA') || this.pressed.has('ArrowLeft'));
		let forward = Number(this.pressed.has('KeyW') || this.pressed.has('ArrowUp')) - Number(this.pressed.has('KeyS') || this.pressed.has('ArrowDown'));
		const length = Math.hypot(right, forward);
		if (length > 0) {
			right /= length; forward /= length;
			this.following = false;
		}
		const speed = clamp(this.camera.radius * 0.65, 5, 100) * (this.pressed.has('ShiftLeft') || this.pressed.has('ShiftRight') ? 1.65 : 1);
		const acceleration = eased(length > 0 ? 16 : 11, delta);
		this.velocity.right += (right * speed - this.velocity.right) * acceleration;
		this.velocity.forward += (forward * speed - this.velocity.forward) * acceleration;
		if (!this.following) {
			const offset = cameraPanOffset(this.camera.alpha, this.velocity.right * delta, this.velocity.forward * delta);
			this.desiredTarget.x += offset.x; this.desiredTarget.z += offset.z;
		} else {
			this.desiredTarget.set(focusPoint.x, focusPoint.y ?? 0.8, focusPoint.z);
		}
		this.clampTarget();
		this.camera.alpha += cameraAngleDelta(this.camera.alpha, this.desiredAlpha) * eased(14, delta);
		this.camera.beta += (this.desiredBeta - this.camera.beta) * eased(14, delta);
		this.camera.radius += (this.desiredRadius - this.camera.radius) * eased(10, delta);
		const target = Vector3.Lerp(this.camera.target, this.desiredTarget, eased(this.following ? 6 : 12, delta));
		// Preserve orbit geometry while translating the pivot; the default overload
		// recomputes radius/angles from the old absolute position and causes drift.
		this.camera.setTarget(target, false, false, true);
	}

	private frameOverview(): void {
		this.following = false;
		this.desiredTarget.set((this.minX + this.maxX) / 2, Math.max(0.8, this.minY), (this.minZ + this.maxZ) / 2);
		this.desiredBeta = 0.62;
		this.desiredRadius = clamp(Math.hypot(this.maxX - this.minX, this.maxZ - this.minZ) * 0.8, this.minRadius, this.maxRadius);
		this.velocity.right = this.velocity.forward = 0;
		this.clampTarget();
	}

	private clampTarget(): void {
		this.desiredTarget.x = clamp(this.desiredTarget.x, this.minX, this.maxX);
		this.desiredTarget.y = clamp(this.desiredTarget.y, this.minY, this.maxY);
		this.desiredTarget.z = clamp(this.desiredTarget.z, this.minZ, this.maxZ);
	}

	private pointerDown = (event: PointerEvent): void => {
		this.canvas.focus({ preventScroll: true });
		if (event.button !== 1 && event.button !== 2) return;
		event.preventDefault();
		this.drag = { pointer: event.pointerId, button: event.button, x: event.clientX, y: event.clientY };
		this.canvas.setPointerCapture(event.pointerId);
		if (event.button === 1) this.follow(false);
	};

	private pointerMove = (event: PointerEvent): void => {
		const drag = this.drag; if (!drag || drag.pointer !== event.pointerId) return;
		const dx = event.clientX - drag.x; const dy = event.clientY - drag.y;
		drag.x = event.clientX; drag.y = event.clientY;
		if (drag.button === 2) {
			this.desiredAlpha -= dx * 0.005;
			this.desiredBeta = clamp(this.desiredBeta - dy * 0.004, this.camera.lowerBetaLimit!, this.camera.upperBetaLimit!);
		} else {
			const unit = 2 * this.camera.radius * Math.tan(this.camera.fov / 2) / Math.max(1, this.canvas.clientHeight);
			const offset = cameraPanOffset(this.camera.alpha, -dx * unit, dy * unit / Math.max(0.25, Math.cos(this.camera.beta)));
			this.desiredTarget.x += offset.x; this.desiredTarget.z += offset.z; this.clampTarget();
		}
	};

	private pointerUp = (event: PointerEvent): void => {
		if (this.drag?.pointer !== event.pointerId) return;
		this.drag = null;
		if (this.canvas.hasPointerCapture(event.pointerId)) this.canvas.releasePointerCapture(event.pointerId);
	};

	private wheel = (event: WheelEvent): void => {
		event.preventDefault();
		const pixels = event.deltaY * (event.deltaMode === WheelEvent.DOM_DELTA_LINE ? 16 : event.deltaMode === WheelEvent.DOM_DELTA_PAGE ? this.canvas.clientHeight : 1);
		this.desiredRadius = clamp(this.desiredRadius * Math.exp(clamp(pixels, -400, 400) * 0.0015), this.minRadius, this.maxRadius);
	};

	private keyDown = (event: KeyboardEvent): void => {
		const target = event.target;
		if (event.altKey || event.ctrlKey || event.metaKey || target instanceof HTMLElement && target.closest('input,textarea,select,[contenteditable="true"],[role="dialog"],.modal')) return;
		const overlay = document.querySelector<HTMLElement>('#ui .overlay, [role="dialog"][aria-modal="true"]');
		if (overlay && overlay.getClientRects().length && getComputedStyle(overlay).visibility !== 'hidden') return;
		// F is a focus command, so a toolbar/party button may retain DOM focus.
		// Pan keys still require the canvas/body and never move from a UI button.
		if (event.code === 'KeyF') { event.preventDefault(); if (!event.repeat) this.focus(this.latestFocus); return; }
		if (target instanceof HTMLElement && target.closest('button,a')) return;
		if (target !== this.canvas && target !== document.body && target !== document.documentElement) return;
		if (!['KeyW', 'KeyA', 'KeyS', 'KeyD', 'ArrowUp', 'ArrowDown', 'ArrowLeft', 'ArrowRight', 'ShiftLeft', 'ShiftRight'].includes(event.code)) return;
		event.preventDefault(); this.pressed.add(event.code);
	};
	private keyUp = (event: KeyboardEvent): void => { this.pressed.delete(event.code); };
	private clearInput = (): void => { this.pressed.clear(); this.drag = null; this.velocity.right = this.velocity.forward = 0; };
	private visibilityChanged = (): void => { if (document.hidden) this.clearInput(); };

	dispose(): void {
		if (this.disposed) return;
		this.disposed = true; this.abort.abort(); this.clearInput(); this.camera.dispose();
	}
}
