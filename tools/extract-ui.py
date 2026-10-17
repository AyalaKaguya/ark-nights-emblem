"""Extract a small, source-attributed set of original Arknights UI sprites.

Reads selected local game bundles only. Does not modify the game client.
LZ4AK registration is imported from the sibling read-only map extractor.
"""
from __future__ import annotations
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import sys
from PIL import Image, ImageDraw, ImageFont
import UnityPy

spec = importlib.util.spec_from_file_location('hotel_extractor', Path(__file__).with_name('extract-hotel.py'))
hotel = importlib.util.module_from_spec(spec)
spec.loader.exec_module(hotel)

# output, bundle, original Sprite name, adaptation note
SELECTION = [
 ('portraits/amiya.png','spritepack/ui_char_avatar_8.ab','char_002_amiya','Original Amiya default avatar.'),
 ('portraits/hoshiguma.png','spritepack/ui_char_avatar_8.ab','char_136_hsguma','Original Hoshiguma default avatar.'),
 ('portraits/ansel.png','spritepack/ui_char_avatar_9.ab','char_212_ansel','Original Ansel default avatar.'),
 ('portraits/melee.png','spritepack/icon_enemies_0.ab','enemy_1002_nsabr','Original melee enemy icon, matching the prototype Spine model.'),
 ('portraits/ranged.png','spritepack/icon_enemies_0.ab','enemy_1003_ncbow','Original ranged enemy icon, matching the prototype Spine model.'),
 ('skills/amiya.png','spritepack/skill_icons_0.ab','skill_icon_skchr_amiya_2','Original Amiya skill 2 icon; prototype skill rules are independently designed.'),
 ('skills/hoshiguma.png','spritepack/skill_icons_0.ab','skill_icon_skchr_hsguma_2','Original Hoshiguma skill 2 icon; prototype skill rules are independently designed.'),
 ('skills/ansel.png','spritepack/skill_icons_1.ab','skill_icon_skcom_heal_up[1]','Original common healing enhancement alpha icon, used as Ansel healing action representative.'),
 ('icons/move.png','arts/ui/[uc]battlecommon.ab','sprite_direction_arrow','Original direction arrow, repurposed for RPG Move; not an original Move action icon.'),
 ('icons/attack.png','spritepack/skill_icons_1.ab','skill_icon_skcom_atk_up[1]','Original 128px common ATK enhancement alpha skill icon, repurposed for RPG Attack.'),
 ('icons/dash.png','arts/ui/[uc]common.ab','icon_attack_speed','Original attack-speed stat icon, repurposed for RPG Dash.'),
 ('icons/disengage.png','arts/ui/[uc]battlecommon.ab','btn_escape','Original text-free battle retreat icon, repurposed for RPG Disengage.'),
 ('icons/rally.png','arts/ui/[uc]common.ab','icon_hp','Original HP stat icon, repurposed for RPG Rally.'),
 ('icons/interact.png','arts/ui/[uc]common.ab','confirm_icon','Original confirmation icon, repurposed for Interact.'),
 ('icons/inventory.png','arts/ui/[uc]battlecommon.ab','sprite_sandbox_dialog_bag','Original sandbox bag icon, repurposed for inventory.'),
 ('icons/passive.png','arts/ui/[uc]battlecommon.ab','icon_sparkle','Original sparkle icon, repurposed for passive traits.'),
 ('icons/end-turn.png','arts/ui/[uc]battlecommon.ab','btn_play','Original play button icon, repurposed for End Turn.'),
 ('icons/focus.png','arts/ui/[uc]battlecommon.ab','icon_state_normal_outside','Original text-free focus reticle graphic, repurposed for camera/target focus.'),
 ('icons/menu.png','arts/ui/[uc]battlecommon.ab','btn_menu','Original battle menu icon.'),
 ('icons/speed.png','arts/ui/[uc]battlecommon.ab','btn_speed_2x','Original 2x battle speed icon.'),
 ('icons/pause.png','arts/ui/[uc]battlecommon.ab','btn_pause','Original battle pause icon.'),
 ('icons/cancel.png','arts/ui/[uc]common.ab','btn_close','Original text-free close icon, used for Cancel.'),
 ('icons/defense.png','arts/ui/[uc]common.ab','icon_def','Original DEF stat icon.'),
 ('icons/block.png','arts/ui/[uc]common.ab','icon_block','Original Block stat icon.'),
 ('icons/resistance.png','arts/ui/[uc]common.ab','icon_res','Original RES stat icon.'),
 ('icons/time.png','arts/ui/[uc]common.ab','icon_time','Original time icon.'),
 ('professions/caster.png','arts/ui/[uc]battlecommon.ab','icon_profession_caster','Original Caster profession icon.'),
 ('professions/tank.png','arts/ui/[uc]battlecommon.ab','icon_profession_tank','Original Defender profession icon.'),
 ('professions/medic.png','arts/ui/[uc]battlecommon.ab','icon_profession_medic','Original Medic profession icon.'),
 ('professions/melee.png','arts/ui/[uc]battlecommon.ab','icon_profession_warrior','Original Guard profession icon, representative of a melee enemy.'),
 ('professions/ranged.png','arts/ui/[uc]battlecommon.ab','icon_profession_sniper','Original Sniper profession icon, representative of a ranged enemy.'),
 ('frames/skill.png','arts/ui/[uc]battlecommon.ab','skill_02_frame','Original skill frame.'),
 ('frames/portrait.png','arts/ui/[uc]battlecommon.ab','sprite_charactercard_underframe','Original operator card underframe.'),
 ('frames/battle-menu.png','arts/ui/[uc]battlecommon.ab','sprite_battlemenu_frame','Original battle menu frame.'),
 ('frames/character-menu.png','arts/ui/[uc]battlecommon.ab','sprite_character_menu_frame','Original character menu frame.'),
 ('frames/rectangle.png','arts/ui/[uc]battlecommon.ab','sprite_rectangle_frame_full','Original full rectangular frame.'),
 ('frames/rectangle-triangle.png','arts/ui/[uc]battlecommon.ab','sprite_rectangle_frame_triangle','Original triangular-corner frame.'),
 ('frames/circle.png','arts/ui/[uc]battlecommon.ab','sprite_circle','Original circle graphic.'),
 ('frames/ring.png','arts/ui/[uc]battlecommon.ab','sprite_respawn_ring','Original respawn ring.'),
 ('frames/skill-panel.png','arts/ui/[uc]battlecommon.ab','sprite_skill_panel','Original skill panel background.'),
 ('frames/info-panel.png','arts/ui/[uc]battlecommon.ab','sprite_character_info_back','Original character information panel.'),
 ('frames/round-panel.png','arts/ui/[uc]common.ab','back_round','Original rounded panel background.'),
 ('frames/item.png','arts/ui/[uc]battlecommon.ab','icon_item_bkg','Original item background.'),
 ('frames/talent.png','arts/ui/[uc]battlecommon.ab','talent_back','Original talent background.'),
 ('items/rally.png','arts/ui_item_icons_1.ab','ap_supply_lt_60','Original limited AP supply item icon; only this slot is mapped to the existing Rally command, not its original AP effect.'),
 ('items/supply.png','arts/ui_item_icons_0.ab','ap_supply_lt_120','Original limited AP supply item icon; inventory display only, no new gameplay effect.'),
 ('items/food.png','arts/ui_item_icons_0.ab','ap_supply_lt_100_2025_5','Original 2025 event AP supply sandwich icon; inventory display only, no new gameplay effect.'),
 ('items/currency.png','arts/ui_item_icons_4.ab','GOLD','Original LMD currency icon; inventory display only, no new gameplay effect.'),
 ('items/material.png','arts/ui_item_icons_5.ab','MTL_GOLD1','Original material icon; inventory display only, no new gameplay effect.'),
 ('items/manual.png','arts/ui_item_icons_5.ab','MTL_SKILL3','Original skill summary material icon; inventory display only, no new gameplay effect.'),
]

def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest()

def main():
 ap=argparse.ArgumentParser();ap.add_argument('--client',type=Path,default=hotel.DEFAULT_CLIENT);ap.add_argument('--out',type=Path,default=Path(__file__).resolve().parents[1]/'public/ui');args=ap.parse_args()
 args.out.mkdir(parents=True,exist_ok=True)
 grouped={}
 for selection in SELECTION:grouped.setdefault(selection[1],[]).append(selection)
 sources=[];assets=[];missing=[]
 for relative, selections in grouped.items():
  path=args.client/relative
  print('READ',relative,flush=True)
  env=UnityPy.load(str(path));objects={}
  for obj in env.objects:
   if obj.type.name=='Sprite':
    d=obj.read();objects.setdefault(d.m_Name,[]).append((obj,d))
  sources.append({'relativePath':relative,'bytes':path.stat().st_size,'sha256':sha(path)})
  for output,_,name,note in selections:
   candidates=objects.get(name,[])
   if not candidates:
    missing.append({'output':output,'name':name,'bundle':relative});continue
   obj,data=candidates[0]
   try:
    image=data.image.convert('RGBA');target=args.out/output;target.parent.mkdir(parents=True,exist_ok=True);image.save(target)
    border=getattr(data,'m_Border',None)
    record={'path':'/ui/'+output,'sourceBundle':relative,'sourceSprite':name,'sourcePathId':str(obj.path_id),'size':list(image.size),'sha256':sha(target),'note':note,'spriteBorder':{k:float(getattr(border,k)) for k in 'xyzw'} if border else None}
    assets.append(record);print('SAVED',output,image.size,flush=True)
   except Exception as exc:missing.append({'output':output,'name':name,'bundle':relative,'error':str(exc)})
 manifest={'version':1,'source':'Original sprites from the locally installed Arknights PC client; source bundles read-only.','rights':'All original Arknights artwork belongs to Hypergryph and respective rights holders. Extracting it grants no new license. No Baldurs Gate 3 artwork is used.','adaptationBoundary':'RPG action names are this prototype mappings. move/dash/disengage/rally/interact/passive/end-turn/focus reuse documented original stat or UI symbols; the source game does not have those DnD action semantics. PNG pixels are original cropped sprites; no fabricated artwork.','assets':assets,'sources':sources,'missing':missing}
 (args.out/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf8')
 cols=6;cellw=200;cellh=190;rows=(len(assets)+cols-1)//cols;canvas=Image.new('RGB',(cols*cellw,rows*cellh),'#262d30');draw=ImageDraw.Draw(canvas)
 try:font=ImageFont.truetype('C:/Windows/Fonts/arial.ttf',13)
 except Exception:font=None
 for i,asset in enumerate(assets):
  image=Image.open(args.out/asset['path'].removeprefix('/ui/'));image.thumbnail((160,140));x=i%cols*cellw+(cellw-image.width)//2;y=i//cols*cellh+12;canvas.paste(image,(x,y),image);draw.text((i%cols*cellw+7,i//cols*cellh+155),asset['path'][4:],fill='#eee3cb',font=font)
 canvas.save(args.out/'contact-sheet.jpg',quality=92)
 print('DONE',len(assets),'assets',len(missing),'missing',flush=True)
 print('MISSING',missing,flush=True)

if __name__=='__main__':
 sys.stdout.reconfigure(encoding='utf8');main()
