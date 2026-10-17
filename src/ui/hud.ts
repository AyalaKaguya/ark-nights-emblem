import type { BattleState, Unit } from '../rules';
import { renderMinimap } from './minimap';

export type HotbarTab = 'common' | 'items' | 'passive';
export interface HudView {
 mode: string; battle: BattleState | null; party: Unit[]; active: Unit | null; selected: string;
 intent: 'move' | 'attack' | 'skill'; checkedIn: boolean; supplies: boolean; cleared: boolean;
 nearest: string | null; paused: boolean; dialogue: string; speed: number; tab: HotbarTab;
 canRetry: boolean; inventory: boolean;
}
const base = import.meta.env.BASE_URL;
const esc = (s: string) => s.replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]!));
export const uiAsset = (file: string) => `${base}ui/${file}.png`;
const icon = (file: string, className = '') => `<img class="${className}" src="${uiAsset(file)}" alt="" draggable="false">`;
const portrait = (u: Unit) => `portraits/${u.team === 'party' ? u.id : u.role}`;
const profession = (u: Unit) => `professions/${u.role === 'healer' ? 'medic' : u.role}`;
const nameOfSkill: Record<string, string> = { caster:'术式爆发', tank:'护卫姿态', healer:'急救术式' };
const utility = (id: string, image: string, label: string, extra = '') => `<button type="button" class="utility-button" data-action="${id}" aria-label="${label}" ${extra}>${icon(image)}</button>`;
const slots = (count: number) => Array.from({length:count},()=>'<span class="empty-slot" aria-hidden="true"></span>').join('');
function actionSlot(id: string, image: string, label: string, usable: boolean, selected = false, variant = '') {
 return `<button type="button" class="action-slot ${selected ? 'is-selected' : ''} ${variant}" data-action="${id}" aria-label="${label}" ${usable ? '' : 'disabled'}>${icon(image)}<span class="slot-sheen"></span></button>`;
}
function partyRail(view: HudView) {
 return `<aside class="party-rail" aria-label="队伍">${view.party.map(u=>`<button type="button" class="party-portrait ${view.selected === u.id ? 'is-selected' : ''} ${u.hp <= 0 ? 'is-dead' : ''} ${view.active?.id === u.id ? 'is-current' : ''}" data-unit="${u.id}" aria-label="${u.name}"><span class="portrait-art">${icon(portrait(u))}</span><span class="portrait-frame"></span><span class="portrait-health" style="--health:${u.hp/u.maxHp*100}%"></span><span class="portrait-hp">${u.hp}/${u.maxHp}</span><span class="profession-medallion">${icon(profession(u))}</span></button>`).join('')}<span class="party-chain" aria-hidden="true"></span></aside>`;
}
function initiative(view: HudView) {
 if (!view.battle || !['battle','presenting'].includes(view.mode)) return '';
 return `<nav class="turn-order" aria-label="先攻顺序">${view.battle.order.map(id=>{const u=view.battle!.units.find(u=>u.id===id)!;return `<button class="initiative-portrait ${u.id===view.active?.id?'is-current':''} ${u.team==='enemy'?'is-enemy':''} ${u.hp<=0?'is-dead':''}" data-unit="${u.id}" aria-label="${u.name}" ${u.hp<=0?'disabled':''}>${icon(portrait(u))}<span class="initiative-health" style="--health:${u.hp/u.maxHp*100}%"></span></button>`;}).join('')}<span class="round-counter">${view.battle.round}</span></nav>`;
}
function resources(view: HudView, u: Unit) {
 const inBattle=!!view.battle && ['battle','presenting'].includes(view.mode);
 const budget = inBattle ? view.active?.budget ?? u.budget : {movement:9,action:1,bonus:1,reaction:1};
 return `<div class="resource-counters" aria-label="行动资源"><span class="resource move-resource" aria-label="移动 ${budget.movement.toFixed(1)} 米">${icon('icons/move')}<b>${budget.movement.toFixed(1)}</b></span><span class="resource-pip main-pip ${budget.action?'':'spent'}" aria-label="主要动作 ${budget.action}"></span><span class="resource-pip bonus-pip ${budget.bonus?'':'spent'}" aria-label="附赠动作 ${budget.bonus}"></span><span class="resource-pip reaction-pip ${budget.reaction?'':'spent'}" aria-label="反应 ${budget.reaction}"></span></div>`;
}
function hotbar(view: HudView) {
 const inBattle = ['battle','presenting'].includes(view.mode);
 const actor = inBattle ? view.active ?? view.party[0] : view.party.find(u=>u.id===view.selected) ?? view.party[0];
 const partyActor = actor.team === 'party' ? actor : view.party.find(u=>u.id===view.selected) ?? view.party[0];
 const usable = view.mode==='battle' && actor.team==='party' && !view.paused;
 const main = usable && actor.budget.action>0;
 let grid='';
 if(view.tab==='common') {
  grid = `<div class="slot-grid common-grid">${actionSlot('move','icons/move','移动',usable,view.intent==='move','movement')}${actionSlot('attack','icons/attack','普攻',main,view.intent==='attack','offensive')}${actionSlot('skill',`skills/${partyActor.id}`,nameOfSkill[partyActor.role]??'技能',main,view.intent==='skill','signature')}${actionSlot('dash','icons/dash','疾走',main,false,'movement')}${actionSlot('disengage','icons/disengage','撤离',main,false,'movement')}${actionSlot('rally','items/rally','振作',usable&&actor.budget.bonus>0&&!actor.rallyUsed&&actor.hp<actor.maxHp,false,'restorative')}${slots(14)}</div>`;
 } else if(view.tab==='items') {
  grid = `<div class="slot-grid item-grid">${actionSlot('rally','items/rally','振作',usable&&actor.budget.bonus>0&&!actor.rallyUsed&&actor.hp<actor.maxHp,false,'restorative')}${view.supplies ? `<span class="inventory-item" aria-label="旅行补给">${icon('items/supply')}<small>1</small></span>` : '<span class="empty-slot" aria-hidden="true"></span>'}${slots(18)}</div>`;
 } else {
  grid=`<div class="slot-grid passive-grid"><span class="stat-slot" aria-label="防御 ${partyActor.defense}">${icon('icons/defense')}<b>${partyActor.defense}</b></span><span class="stat-slot" aria-label="法术抗性 ${partyActor.resistance}">${icon('icons/resistance')}<b>${partyActor.resistance}</b></span><span class="stat-slot ${partyActor.guarding?'is-active':''}" aria-label="护卫姿态">${icon('skills/hoshiguma')}</span><span class="stat-slot ${partyActor.budget.reaction?'is-active':''}" aria-label="反应">${icon('icons/block')}</span>${slots(16)}</div>`;
 }
 const exploreLabel = view.cleared ? '继续探索' : !view.checkedIn?'办理入住':!view.supplies?'领取补给':'前往庭院';
 return `<footer class="hotbar" aria-label="动作栏"><div class="selected-panel"><button class="character-medallion" data-action="focus" aria-label="聚焦 ${partyActor.name}"><span class="medallion-art">${icon(portrait(partyActor))}</span><span class="medallion-frame"></span><span class="medallion-hp">${partyActor.hp}/${partyActor.maxHp}</span></button><span class="selected-name">${partyActor.name}</span><div class="selected-utilities">${utility('inventory','icons/inventory','物品')}${utility('focus','icons/focus','聚焦')}</div></div><div class="hotbar-body">${resources(view,actor)}<div class="hotbar-ornament" aria-hidden="true"></div>${grid}<nav class="hotbar-tabs" aria-label="动作分类">${(['common','items','passive'] as const).map((tab,i)=>`<button class="hotbar-tab ${view.tab===tab?'is-selected':''}" data-tab="${tab}" aria-label="${['常用','物品','被动'][i]}" aria-pressed="${view.tab===tab}">${['常用','物品','被动'][i]}</button>`).join('')}</nav></div><div class="end-turn-panel"><button class="turn-end ${!inBattle?'exploration-end':''}" data-action="${inBattle?'endTurn':'next'}" aria-label="${inBattle?'结束回合':exploreLabel}" ${inBattle&&!usable||view.mode==='forming'?'disabled':''}>${icon(inBattle?'icons/time':'icons/interact')}<span class="end-ring" aria-hidden="true"></span></button><div class="utility-cluster">${utility('speed','icons/speed',view.speed===99?'跳过演出':`${view.speed}×`)}${view.nearest&&!inBattle?`<button class="utility-button" data-interaction="${view.nearest}" aria-label="交互">${icon('icons/interact')}</button>`:utility('focus','icons/focus','聚焦小队')}</div></div></footer>`;
}
function pauseMenu(view: HudView) {
 return `<div class="overlay pause-overlay"><section class="pause-menu modal" role="dialog" aria-modal="true" aria-label="暂停菜单"><h2>暂停</h2><button class="menu-option" data-action="help">继续</button><button class="menu-option" data-action="replay" ${view.canRetry?'':'disabled'}>重新挑战</button><button class="menu-option" data-action="title">返回标题</button></section></div>`;
}
export function renderHud(view: HudView): string {
 if (view.mode==='loading') return `<div class="loading-screen"><span class="loading-emblem">${icon('skills/amiya')}</span><span class="loading-line"><i></i></span></div>`;
 if (view.mode==='error') return `<div class="loading-screen">${utility('reload','icons/interact','重新加载')}</div>`;
 if (view.mode==='title') return `<section class="title-screen"><div class="title-seal">${icon('skills/amiya')}</div><h1>黄昏旅邸</h1><button class="title-start" data-action="start">开始旅途</button>${utility('help','icons/menu','菜单')}</section>${view.paused?pauseMenu(view):''}`;
 let overlay = '';
 if (view.mode==='dialogue') overlay = `<div class="dialogue-veil"><section class="dialogue-panel" role="dialog" aria-modal="true" aria-label="接待员"><div class="dialogue-speaker">接待员</div><p>${view.dialogue}</p><button class="dialogue-continue" data-action="closeDialogue" aria-label="继续">${icon('icons/end-turn')}</button></section></div>`;
 if(view.mode==='victory'||view.mode==='defeat') overlay=`<div class="overlay outcome-overlay"><section class="outcome-panel modal" role="dialog" aria-modal="true" aria-label="${view.mode==='victory'?'胜利':'失败'}"><span class="outcome-seal">${icon(view.mode==='victory'?'skills/hoshiguma':'icons/disengage')}</span><h2>${view.mode==='victory'?'庭院重归宁静':'暂时撤退'}</h2><button class="menu-option" data-action="${view.mode==='victory'?'continue':'retry'}">${view.mode==='victory'?'继续探索':'重新挑战'}</button></section></div>`;
 return `<div class="hud ${view.mode==='forming'?'is-forming':''}">${partyRail(view)}${initiative(view)}<aside class="minimap" aria-label="地图"><span class="map-location">黄昏旅邸</span><div class="minimap-circle">${renderMinimap()}</div><span class="map-north" aria-hidden="true">N</span><div class="map-utilities">${utility('mapOut','icons/move','缩小地图')}${utility('mapZoom','icons/focus','放大地图')}${utility('help','icons/menu','菜单')}</div></aside>${hotbar(view)}</div>${overlay}${view.paused?pauseMenu(view):''}`;
}
