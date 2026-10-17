import { INTERACTIONS } from '../shared';
import type { Point } from '../shared';

export interface MinimapState {
	positions: { id: string; team: 'party' | 'enemy'; selected: boolean; point: Point }[];
	focus: Point;
	/** 2 shows 32 m, 5 shows 12.8 m across the circle. */
	zoom: number;
	/** Babylon orbit alpha, radians. The map stays north-up. */
	heading: number;
}

// Orthographic capture of the original client geometry: 64 × 64 world metres.
// Up is +Z. Texture is not a schematic or a picture of a different game's UI.
export const MINIMAP_BOUNDS = { minX: -8, maxX: 56, minZ: -12, maxZ: 52 } as const;
const BASE = import.meta.env.BASE_URL;
const NS = 'http://www.w3.org/2000/svg';
const pointOnMap = (point: Point): Point => ({ x: point.x - MINIMAP_BOUNDS.minX, z: MINIMAP_BOUNDS.maxZ - point.z });
let previousActors = '';
let previousSvg: SVGSVGElement | null = null;

/** SVG-only markup: the enclosing HUD owns frame, label, north sign and zoom
 * controls. No visible copy is rendered inside the clipped circular map.
 */
export function renderMinimap(): string {
	return `<svg id="ark-minimap" viewBox="0 0 200 200" width="100%" height="100%" role="img" aria-label="黄昏旅邸原地图" style="display:block;border-radius:50%">
				<defs>
					<clipPath id="ark-map-clip"><circle cx="100" cy="100" r="97"/></clipPath>
					<radialGradient id="ark-map-vignette"><stop offset="55%" stop-color="#041c12" stop-opacity="0"/><stop offset="100%" stop-color="#041c12" stop-opacity=".64"/></radialGradient>
				</defs>
				<g clip-path="url(#ark-map-clip)">
					<rect width="200" height="200" fill="#1b3026"/>
					<g data-map-terrain><image href="${BASE}ui/minimap.png" x="0" y="0" width="64" height="64"/></g>
					<g data-map-landmarks></g><g data-map-units></g>
					<rect width="200" height="200" fill="url(#ark-map-vignette)" pointer-events="none"/>
				</g>
				<circle cx="100" cy="100" r="97" fill="none" stroke="#b9a46b" stroke-width="1.1"/>
				<circle cx="100" cy="100" r="93.5" fill="none" stroke="#736b46" stroke-width=".5" opacity=".8"/>
				<g data-map-camera><path d="M94 89l6-10 6 10-6-3z" fill="#f4e3af" stroke="#1a3027" stroke-width=".7" opacity=".95"/></g>
			</svg>`;
}

/** Update a freshly rendered or retained HUD without changing map orientation.
 * The only HTML generated from state is fixed SVG; untrusted actor ids never
 * enter markup or selectors. Positions are clamped at the circle's interior.
 */
export function updateMinimap(state: MinimapState): void {
	const svg = document.querySelector<SVGSVGElement>('#ark-minimap'); if (!svg) return;
	const zoom = Number.isFinite(state.zoom) ? Math.max(2, Math.min(5, state.zoom)) : 3;
	const focus = pointOnMap(state.focus), scale = 200 / 64 * zoom;
	const tx = 100 - focus.x * scale, ty = 100 - focus.z * scale;
	const terrain = svg.querySelector<SVGGElement>('[data-map-terrain]');
	terrain?.setAttribute('transform', `translate(${tx.toFixed(3)} ${ty.toFixed(3)}) scale(${scale.toFixed(5)})`);
	const screen = (point: Point): Point => {
		const map = pointOnMap(point); let x = (map.x - focus.x) * scale, z = (map.z - focus.z) * scale;
		const length = Math.hypot(x, z); if (length > 89) { x *= 89 / length; z *= 89 / length; }
		return { x: x + 100, z: z + 100 };
	};
	const landmarkGroup = svg.querySelector('[data-map-landmarks]');
	if (landmarkGroup) {
		landmarkGroup.replaceChildren(...INTERACTIONS.map(interaction => {
			const p = screen(interaction), marker = document.createElementNS(NS, 'path');
			marker.setAttribute('d', `M${p.x.toFixed(2)} ${(p.z - 3.5).toFixed(2)}l3.5 3.5-3.5 3.5-3.5-3.5z`);
			marker.setAttribute('fill', '#d4b563'); marker.setAttribute('stroke', '#372f1a'); marker.setAttribute('stroke-width', '1');
			return marker;
		}));
	}
	const key = JSON.stringify(state.positions.map(actor => [actor.id, actor.team, actor.selected, actor.point.x.toFixed(3), actor.point.z.toFixed(3)])) + `/${focus.x}/${focus.z}/${zoom}`;
	const units = svg.querySelector('[data-map-units]');
	if (units && (key !== previousActors || svg !== previousSvg)) {
		units.replaceChildren(...state.positions.filter(actor => Number.isFinite(actor.point.x) && Number.isFinite(actor.point.z)).map(actor => {
			const p = screen(actor.point), marker = document.createElementNS(NS, 'circle');
			marker.setAttribute('cx', p.x.toFixed(2)); marker.setAttribute('cy', p.z.toFixed(2)); marker.setAttribute('r', actor.selected ? '4.3' : '3.3');
			marker.setAttribute('fill', actor.team === 'enemy' ? '#b83f32' : actor.selected ? '#f3e5b3' : '#79b59a');
			marker.setAttribute('stroke', actor.selected ? '#f5d990' : '#18342b'); marker.setAttribute('stroke-width', actor.selected ? '1.6' : '1.2');
			return marker;
		}));
		previousActors = key; previousSvg = svg;
	}
	// Camera looks opposite its orbital position. Map remains fixed; only this
	// small heading arrow rotates around the central selected/focus marker.
	const degrees = Number.isFinite(state.heading) ? state.heading * 180 / Math.PI + 90 : 0;
	svg.querySelector('[data-map-camera]')?.setAttribute('transform', `rotate(${degrees.toFixed(2)} 100 100)`);
	svg.dataset.zoom = zoom.toString();
}
