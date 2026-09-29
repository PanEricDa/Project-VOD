/* 浏览器交互与绘制；simulation.js 独立负责规则，可直接双击 index.html 游玩。 */
(() => {
  'use strict';
  const {World,W,H,dist,clamp}=SquadSim;
  const $=id=>document.getElementById(id),canvas=$('arena'),ctx=canvas.getContext('2d');
  let world=new World(),started=false,paused=false,mode='normal',pointer={x:600,y:370},keys=new Set(),last=0,uiClock=0,shownResult=false,toastUntil=0,toast='',audio=null;
  const intro=`<p>你是先锋，另外四名队友自动完成坦克、治疗和输出。先把怪带到队伍附近，再决定优先目标与爆发落点。</p><div class="keys"><b>W A S D</b><span>移动先锋，接近敌群开战</span><b>Q</b><span>180 范围挑衅，临时高仇恨持续 5 秒</span><b>E / 右键</b><span>设定鼠标处的交战点；F 恢复跟随</span><b>单击敌人</b><span>标记优先目标，输出角色优先攻击</span><b>Tab → 单击</b><span>进入慢速，预览并确认集中爆发</span><b>Esc / Space</b><span>取消指令 / 暂停</span></div><p>远程怪不会因为被挑衅就贴身。黄色圈是精英强化范围，紫色实心预警区请及时避开。阵地和优先目标不消耗专注。</p><p class="stat-note">建议使用键盘鼠标；点击“进入战场”后即可操作。切换窗口会自动暂停。</p>`;
  function tone(freq=320,duration=.06){try{if(!audio)return;const osc=audio.createOscillator(),gain=audio.createGain();osc.connect(gain);gain.connect(audio.destination);osc.frequency.value=freq;gain.gain.setValueAtTime(.035,audio.currentTime);gain.gain.exponentialRampToValueAtTime(.001,audio.currentTime+duration);osc.start();osc.stop(audio.currentTime+duration);}catch{}}
  function notify(text){toast=text;toastUntil=performance.now()+2500;}
  function showIntro(){ $('dialog-title').textContent='由你决定，在哪里打。';$('dialog-body').innerHTML=intro;$('start').textContent=started?'返回战场':'进入战场';$('overlay').classList.remove('hidden'); }
  function reset(){world=new World({scenario:$('scenario').value,hpScale:Number($('hp-scale').value),damageScale:Number($('damage-scale').value)});mode='normal';paused=false;started=true;shownResult=false;keys.clear();$('overlay').classList.add('hidden');canvas.focus();notify('先靠近第一群敌人，Q 挑衅后带回队伍。');updateUI();}
  function available(){return started&&!paused&&world.state==='playing'&&$('overlay').classList.contains('hidden');}
  function action(name){if(!available())return;
    if(name==='taunt'){if(world.taunt()){tone(240);notify('临时仇恨生效 · 带怪走向队伍');}else notify(world.tauntCD>0?`挑衅冷却 ${world.tauntCD.toFixed(1)} 秒`:world.logs[0].message);}
    if(name==='anchor'){mode=mode==='anchor'?'normal':'anchor';notify(mode==='anchor'?'选择交战位置：单击地面确认，Esc 取消':'取消位置指令');}
    if(name==='follow'){world.setAnchor(null);mode='normal';notify('恢复跟随 · 可以带队转移');}
    if(name==='burst'){if(mode==='burst'){mode='normal';return;}if(world.focus<45||world.burstCD>0){notify(world.focus<45?'专注不足：常态有效伤害与击杀恢复专注':`爆发冷却 ${world.burstCD.toFixed(1)} 秒`);return;}mode='burst';notify('专注慢速 · 选择落点，单击确认 / Esc 取消');tone(520,.12);}
    updateUI();
  }
  function togglePause(){if(!started||world.state!=='playing'||!$('overlay').classList.contains('hidden'))return;paused=!paused;keys.clear();updateUI();}
  $('start').onclick=()=>{if(!started||shownResult){reset();}else{$('overlay').classList.add('hidden');paused=false;canvas.focus();}try{audio=audio||new(window.AudioContext||window.webkitAudioContext)();audio.resume();}catch{}};
  $('help').onclick=()=>{if(world.state!=='playing')return;paused=true;keys.clear();showIntro();};
  $('pause').onclick=togglePause;$('restart').onclick=reset;$('apply').onclick=reset;
  for(const name of ['taunt','anchor','follow','burst'])$(name).onclick=()=>action(name);
  $('hp-scale').oninput=()=>{$('hp-label').textContent=Number($('hp-scale').value).toFixed(1)+'×';};$('damage-scale').oninput=()=>{$('damage-label').textContent=Number($('damage-scale').value).toFixed(1)+'×';};
  window.addEventListener('keydown',e=>{
    if(['INPUT','SELECT'].includes(e.target.tagName))return;
    const codes=['KeyW','KeyA','KeyS','KeyD','KeyQ','KeyE','KeyF','Tab','Space','Escape'];if(!codes.includes(e.code))return;
    e.preventDefault();if(e.repeat)return;
    if(e.code==='Space'){togglePause();return;}
    if(e.code==='Escape'){mode='normal';if(!shownResult&&started&&!$('overlay').classList.contains('hidden')){$('overlay').classList.add('hidden');paused=false;}updateUI();return;}
    if(!available())return;keys.add(e.code);
    if(e.code==='KeyQ')action('taunt');if(e.code==='KeyE'){if(world.setAnchor(pointer)){notify('交战位置已更新');tone(380);}else notify('该位置无法站立');}
    if(e.code==='KeyF')action('follow');if(e.code==='Tab')action('burst');
  });
  window.addEventListener('keyup',e=>keys.delete(e.code));
  window.addEventListener('blur',()=>{keys.clear();if(started&&!shownResult)paused=true;updateUI();});
  document.addEventListener('visibilitychange',()=>{if(document.hidden&&started&&!shownResult){paused=true;keys.clear();}});
  function updatePointer(e){const r=canvas.getBoundingClientRect();pointer={x:clamp((e.clientX-r.left)/r.width*W,0,W),y:clamp((e.clientY-r.top)/r.height*H,0,H)};}
  canvas.addEventListener('pointermove',updatePointer);
  canvas.addEventListener('pointerdown',e=>{e.preventDefault();canvas.focus();updatePointer(e);if(!available())return;
    if(e.button===2){if(mode==='burst'){mode='normal';notify('取消爆发，未消耗专注');}else if(world.setAnchor(pointer))notify('交战位置已更新');else notify('该位置无法站立');return;}
    if(e.button!==0)return;
    if(mode==='burst'){if(world.burst(pointer)){mode='normal';tone(150,.2);notify('集中进攻！坦克与治疗继续维持战线。');}else notify(world.logs[0].message);}
    else if(mode==='anchor'){if(world.setAnchor(pointer)){mode='normal';notify('交战位置已更新');}else notify('该位置无法站立');}
    else{const enemy=world.enemies.filter(e=>e.hp>0&&dist(e,pointer)<e.r+14).sort((a,b)=>dist(a,pointer)-dist(b,pointer))[0];world.setMark(enemy||null);if(enemy){tone(410);notify(`优先击杀 ${enemy.name}`);}}
    updateUI();
  });canvas.addEventListener('contextmenu',e=>e.preventDefault());
  function circle(x,y,r,fill,stroke,width=1){ctx.beginPath();ctx.arc(x,y,r,0,Math.PI*2);if(fill){ctx.fillStyle=fill;ctx.fill();}if(stroke){ctx.strokeStyle=stroke;ctx.lineWidth=width;ctx.stroke();}}
  function line(a,b,color,width=1,dash=[]){ctx.beginPath();ctx.setLineDash(dash);ctx.moveTo(a.x,a.y);ctx.lineTo(b.x,b.y);ctx.strokeStyle=color;ctx.lineWidth=width;ctx.stroke();ctx.setLineDash([]);}
  function label(text,x,y,color='#91a9b9',size=12,align='center'){ctx.font=`${size}px "Segoe UI","Microsoft YaHei",sans-serif`;ctx.fillStyle=color;ctx.textAlign=align;ctx.fillText(text,x,y);}
  function drawUnit(u){
    if(u.hp<=0){line({x:u.x-7,y:u.y-7},{x:u.x+7,y:u.y+7},u.ally?u.color+'77':'#604349');line({x:u.x+7,y:u.y-7},{x:u.x-7,y:u.y+7},u.ally?u.color+'77':'#604349');return;}
    const r=u.r;ctx.save();ctx.translate(u.x,u.y);ctx.fillStyle=u.color;ctx.strokeStyle=u.ally?'#e7f9ff':'#331d2b';ctx.lineWidth=1.5;ctx.beginPath();
    if(u.role==='hero'){ctx.rotate(u.face);ctx.moveTo(r+4,0);ctx.lineTo(-r,r*.8);ctx.lineTo(-r*.6,0);ctx.lineTo(-r,-r*.8);ctx.closePath();}
    else if(u.role==='guardian'){ctx.moveTo(-r,-r);ctx.lineTo(r,-r);ctx.lineTo(r,r*.45);ctx.lineTo(0,r+4);ctx.lineTo(-r,r*.45);ctx.closePath();}
    else if(['ranged','archer','caster','mage'].includes(u.role)){ctx.moveTo(0,-r-2);ctx.lineTo(r,0);ctx.lineTo(0,r+2);ctx.lineTo(-r,0);ctx.closePath();}
    else if(u.role==='elite'){for(let i=0;i<6;i++){let a=i*Math.PI/3;ctx.lineTo(Math.cos(a)*r,Math.sin(a)*r);}ctx.closePath();}
    else ctx.arc(0,0,r,0,Math.PI*2);
    ctx.fill();ctx.stroke();if(u.role==='priest'){ctx.strokeStyle='#1f4e3f';ctx.lineWidth=3;ctx.beginPath();ctx.moveTo(-6,0);ctx.lineTo(6,0);ctx.moveTo(0,-6);ctx.lineTo(0,6);ctx.stroke();}ctx.restore();
    const bw=u.ally?40:30;ctx.fillStyle='#050b11';ctx.fillRect(u.x-bw/2,u.y-r-11,bw,4);ctx.fillStyle=u.hp/u.maxHP<.3?'#ff6475':u.color;ctx.fillRect(u.x-bw/2,u.y-r-11,bw*u.hp/u.maxHP,4);
    if(u.ally)label(u.name,u.x,u.y+r+18,u.color,11);
    if(!u.ally&&!u.active)label('休眠',u.x,u.y+r+14,'#61727d',9);
    if(u.lureUntil>world.t){circle(u.x,u.y,r+5,null,'#64e8da',2);label((u.lureUntil-world.t).toFixed(1),u.x,u.y-r-18,'#64e8da',10);}
    if(world.mark===u){circle(u.x,u.y,r+10,null,'#fff0b5',2);label('优先',u.x,u.y-r-22,'#fff0b5',12);}
  }
  function draw(){ctx.clearRect(0,0,W,H);ctx.fillStyle='#101b25';ctx.fillRect(0,0,W,H);
    for(let x=0;x<W;x+=40)line({x,y:0},{x,y:H},'#1a2a36');for(let y=0;y<H;y+=40)line({x:0,y},{x:W,y},'#1a2a36');
    ctx.fillStyle='#142b2e55';ctx.fillRect(30,30,365,H-60);ctx.strokeStyle='#36514f';ctx.setLineDash([6,10]);ctx.strokeRect(30,30,W-60,H-60);ctx.setLineDash([]);
    label('集结区',70,65,'#476966',14,'left');label('近战接触区',620,70,'#526372',13);label('侧翼 / 远程阵地',970,70,'#526372',13);
    for(const o of world.obstacles){ctx.fillStyle='#273643';ctx.fillRect(o.x,o.y,o.w,o.h);ctx.strokeStyle='#50606d';ctx.strokeRect(o.x,o.y,o.w,o.h);for(let y=o.y+10;y<o.y+o.h;y+=18)line({x:o.x+8,y},{x:o.x+o.w-8,y:y+8},'#354956');}
    for(const e of world.enemies.filter(e=>e.hp>0&&e.role==='elite'))circle(e.x,e.y,155,'#b7772110','#c89e4340');
    if(world.anchor){circle(world.anchor.x,world.anchor.y,110,'#4f9eaa0b','#61b4c277');circle(world.anchor.x,world.anchor.y,8,null,'#9bddd9',2);line({x:world.anchor.x-15,y:world.anchor.y},{x:world.anchor.x+15,y:world.anchor.y},'#9bddd9');line({x:world.anchor.x,y:world.anchor.y-15},{x:world.anchor.x,y:world.anchor.y+15},'#9bddd9');label('交战中心',world.anchor.x,world.anchor.y+140,'#8cb9c1',12);}
    for(const z of world.zones){circle(z.x,z.y,z.r,'#d17deb24','#e192eb',2);circle(z.x,z.y,z.r*(1-z.remaining/z.max),'#e58cf72b');label('落雷',z.x,z.y,'#efb2fd');}
    if($('threat-lines').checked)for(const e of world.engaged())if(e.target?.hp>0)line(e,e.target,e.target===world.hero?'#66e8dc60':'#dd9b6840',1,[4,5]);
    if(mode==='burst'){
      const p=world.burstPreview(pointer);const color=p.valid?'#f4da8e':'#ff8b90';circle(pointer.x,pointer.y,135,p.valid?'#ebd27c15':'#ee778811',color,2);
      for(const a of world.allies.filter(a=>a.hp>0&&['caster','archer'].includes(a.role))){circle(a.x,a.y,400,null,a.color+'20');line(a,pointer,p.ready.includes(a)?a.color+'bb':'#df777760',2,[7,5]);}
      label(`${p.targets.length} 个目标 · ${p.ready.length}/2 名输出可参与`,pointer.x,clamp(pointer.y-151,25,H-25),color,14);
      for(const e of p.targets)circle(e.x,e.y,e.r+5,null,color,2);
    }else if(mode==='anchor'){circle(pointer.x,pointer.y,110,'#79cfc511',world.validPoint(pointer,25)?'#7fcac2':'#ee7788',2);label('单击部署交战点',pointer.x,pointer.y-120,'#9bddcf',14);}
    if(keys.has('KeyQ')&&world.hero.hp>0)circle(world.hero.x,world.hero.y,180,null,'#64e8da66');
    for(const u of [...world.enemies,...world.allies])drawUnit(u);
    for(const p of world.projectiles){circle(p.x,p.y,p.burst?5:3,p.color);}
    for(const f of world.fx){const ratio=f.life/f.max;ctx.globalAlpha=clamp(ratio,0,1);if(f.kind==='text')label(f.label,f.x,f.y-(1-ratio)*27,f.color,14);else if(f.kind==='line')line(f,f.to,f.color,3);else if(f.kind==='target')circle(f.x,f.y,f.r,null,f.color,2);else if(f.kind==='nova'){circle(f.x,f.y,f.r*(1-ratio*.6),f.color+'25',f.color,3);}else circle(f.x,f.y,f.r*(1-ratio*.75),null,f.color,f.kind==='death'?3:2);ctx.globalAlpha=1;}
    if(paused&&$('overlay').classList.contains('hidden')){ctx.fillStyle='#08111b99';ctx.fillRect(0,0,W,H);label('已暂停 · Space 继续',W/2,H/2,'#d7f5f0',26);}
    if(world.hero.hp<=0&&world.state==='playing')label('先锋倒下 · 仍可指挥幸存队友',W/2,H-22,'#f6c083',17);
    if(world.settings.scenario==='endurance'&&world.t<48)label(`东侧援军抵达：${Math.ceil(48-world.t)} 秒`,W-45,H-22,'#c99e77',12,'right');
  }
  const clock=t=>`${String(Math.floor(t/60)).padStart(2,'0')}:${String(Math.floor(t%60)).padStart(2,'0')}`;
  function updateUI(){
    $('time').textContent=clock(world.t);$('progress').textContent=`击杀 ${world.metrics.kills} / ${world.total}`;$('engaged').textContent=`交战 ${world.engaged().length}`;
    $('phase').textContent=world.state==='won'?'战场清理完成':world.state==='lost'?'战斗失败':paused?'暂停':mode==='burst'?'专注瞄准 · 0.08×':world.t-world.lastBurst<1.8?'集中进攻':world.engaged().length?'常态战斗':'探索 / 拉怪';
    $('pause').textContent=paused?'继续 · Space':'暂停 · Space';$('focus-value').textContent=`${Math.floor(world.focus)} / 100`;$('focus-fill').style.width=world.focus+'%';
    $('taunt-cd').textContent=world.tauntCD>0?`${world.tauntCD.toFixed(1)}s`:'就绪 · CD 8s';$('burst-cd').textContent=world.burstCD>0?`${world.burstCD.toFixed(1)}s · 45 专注`:'45 专注 · 就绪';$('anchor-state').textContent=world.anchor?'保持阵地':'跟随先锋';
    $('burst').classList.toggle('active',mode==='burst');$('anchor').classList.toggle('active',mode==='anchor'||!!world.anchor);
    $('party').innerHTML=world.allies.map(a=>`<div class="unit-row"><i style="background:${a.color}"></i><div>${a.name}<small>${a.hp>0?a.status:'倒下'}</small><div class="meter"><div style="width:${Math.max(0,a.hp/a.maxHP*100)}%;background:${a.color}"></div></div></div><div class="hp">${Math.ceil(a.hp)} / ${a.maxHP}</div></div>`).join('');
    const active=world.engaged(),lured=active.filter(e=>e.lureUntil>world.t).length;
    $('advice').textContent=mode==='burst'?'鼠标选落点；紫 / 金连线代表可参与的输出，红线代表受阻。坦克与治疗继续维持战线。':lured?`${lured} 个敌人带有临时仇恨，带到 Guardian 附近后等待交接。远程仍遵循射程。`:world.mark?`当前优先处理 ${world.mark.name}。是否值得把火力从杂兵上转移？`:active.some(e=>e.role==='elite')?'光环精英仍在强化附近敌人。可以先处理精英，也可以爆发清掉杂兵降低承伤。':active.length?'观察剩余敌人：继续合波、集中清理，还是移动交战位置？':'第一群在中央缺口右侧。设置交战点后，你可以独自前往拉怪。';
    const preview=world.burstPreview(pointer);$('preview').textContent=mode==='burst'?(preview.valid?`预计覆盖 ${preview.targets.length} 个敌人；实际以技能命中时的位置为准。`:preview.reason):'';
    $('log').innerHTML=world.logs.slice(0,5).map(x=>`<div><span>${clock(x.t)}</span> ${x.message}</div>`).join('');
    $('banner').style.opacity=performance.now()<toastUntil?'1':'0';$('banner').textContent=toast;
  }
  function result(){shownResult=true;mode='normal';keys.clear();const m=world.metrics;$('dialog-title').textContent=world.state==='won'?'战场清理完成':'战斗失败';
    $('dialog-body').innerHTML=`<div class="result-grid"><div>战斗时间<b>${clock(world.t)}</b></div><div>爆发次数<b>${m.bursts}</b></div><div>爆发击杀<b>${m.burstKills} / ${m.kills}</b></div><div>爆发伤害占比<b>${Math.round(m.burstDamage/Math.max(1,m.damage)*100)}%</b></div><div>阵地 / 跟随指令<b>${m.moves}</b></div><div>幸存队员<b>${world.living().length} / 5</b></div></div><p>爆发时刻：${m.burstTimes.length?m.burstTimes.map(clock).join(' → '):'未使用'}</p><p>回想这一局：第二次爆发是否在解决不同的问题？过渡期是在准备下一步，还是等待？可以调整生命 / 爆发倍率，再重试同一布局。</p>`;
    if(world.endReason){const p=document.createElement('p');p.textContent=world.endReason;$('dialog-body').prepend(p);}
    $('start').textContent='同样设置，再试一次';$('overlay').classList.remove('hidden');tone(world.state==='won'?650:130,.3);
  }
  function frame(now){const dt=Math.min((now-last)/1000||0,0.05);last=now;if(available()){world.step(dt*(mode==='burst'?.08:1),{x:(keys.has('KeyD')?1:0)-(keys.has('KeyA')?1:0),y:(keys.has('KeyS')?1:0)-(keys.has('KeyW')?1:0)});if(world.state!=='playing'&&!shownResult)result();}draw();uiClock+=dt;if(uiClock>.1){updateUI();uiClock=0;}requestAnimationFrame(frame);}
  showIntro();updateUI();requestAnimationFrame(frame);
  // 只读调试快照，供浏览器烟雾测试与人工观察；不提供绕过玩法的操作入口。
  window.prototypeSnapshot=()=>({state:world.state,time:world.t,focus:world.focus,mode,paused,hero:{x:world.hero.x,y:world.hero.y,hp:world.hero.hp},allies:world.allies.map(a=>({role:a.role,hp:a.hp,x:a.x,y:a.y})),enemies:world.enemies.map(e=>({role:e.role,hp:e.hp,x:e.x,y:e.y,active:e.active,target:e.target?.role})),metrics:{...world.metrics}});
})();
