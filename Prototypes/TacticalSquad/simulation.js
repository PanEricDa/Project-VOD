/* 独立玩法模拟。所有距离单位为画布像素，时间为游戏秒；不代表 Godot 的正式数值。 */
(function (root) {
  'use strict';
  const W = 1200, H = 740;
  const clamp = (n, a, b) => Math.max(a, Math.min(b, n));
  const dist = (a, b) => Math.hypot(a.x - b.x, a.y - b.y);
  const COLORS = {hero:'#64e8da',guardian:'#69aafa',priest:'#96e596',caster:'#c7a0ff',archer:'#efd080',melee:'#ec827e',ranged:'#edb26b',elite:'#fa6d86',mage:'#df8bf3'};
  const STATS = {
    hero:{hp:240,speed:210,r:13},guardian:{hp:460,speed:130,r:16},priest:{hp:190,speed:142,r:12},caster:{hp:180,speed:140,r:12},archer:{hp:195,speed:153,r:12},
    melee:{hp:100,speed:88,r:11,range:26,damage:9,interval:1.6},ranged:{hp:90,speed:68,r:10,range:240,damage:10,interval:2.1},
    elite:{hp:430,speed:65,r:20,range:38,damage:21,interval:2},mage:{hp:150,speed:66,r:13,range:280,damage:11,interval:2.7}
  };
  const NAMES = {hero:'先锋',guardian:'Guardian',priest:'Priest',caster:'Caster',archer:'Archer',melee:'近战',ranged:'弓手',elite:'光环精英',mage:'施法者'};
  // 线段与矩形相交。pad 是路径规划时为单位半径预留的边界。
  function blocked(a,b,rect,pad=0) {
    let low=0,high=1;
    for(const [s,d,min,max] of [[a.x,b.x-a.x,rect.x-pad,rect.x+rect.w+pad],[a.y,b.y-a.y,rect.y-pad,rect.y+rect.h+pad]]) {
      if(Math.abs(d)<1e-8){if(s<min||s>max)return false;}
      else {let t1=(min-s)/d,t2=(max-s)/d;if(t1>t2)[t1,t2]=[t2,t1];low=Math.max(low,t1);high=Math.min(high,t2);if(low>high)return false;}
    }
    return true;
  }
  class World {
    // settings: scenario 为 skirmish/mixed/endurance；倍率重建战场时生效。
    constructor(settings={}) {
      this.settings={scenario:'mixed',hpScale:1,damageScale:1,...settings};
      this.t=0;this.focus=80;this.state='playing';this.anchor=null;this.mark=null;this.events=[];this.fx=[];this.projectiles=[];this.zones=[];this.queue=[];this.logs=[];
      this.tauntCD=0;this.burstCD=0;this.lastBurst=-100;this.nextId=1;this.noAction=0;
      this.metrics={bursts:0,burstKills:0,burstDamage:0,kills:0,moves:0,marks:0,taunts:0,damage:0,healed:0,burstTimes:[],idle:0};
      this.obstacles=[{x:465,y:105,w:60,h:180},{x:465,y:465,w:60,h:170}];
      this.allies=['hero','guardian','priest','caster','archer'].map((role,i)=>this.unit(role,160-(i>1?60:0),350+[-5,35,-70,85,135][i],true));
      this.hero=this.allies[0];this.enemies=[];this.packs=[];
      const scenario=this.settings.scenario;
      if(scenario==='skirmish')this.addPack(730,350,['melee','melee','melee','melee','melee','ranged']);
      else {
        this.addPack(625,350,['melee','melee','melee','melee','ranged']);
        this.addPack(880,150,['melee','melee','melee','ranged','mage']);
        this.addPack(920,530,['melee','melee','melee','ranged','elite']);
        if(scenario==='endurance')this.queue.push({at:48,kind:'reinforce',x:1040,y:320,roles:['melee','melee','ranged','mage','elite']});
      }
      this.total=this.enemies.length+(scenario==='endurance'?5:0);
      this.log('靠近敌群或使用 Q 开怪。队伍默认跟随先锋。');
    }
    unit(role,x,y,ally=false){const s=STATS[role],hp=s.hp*(ally?1:this.settings.hpScale);return {id:this.nextId++,role,name:NAMES[role],x,y,home:{x,y},r:s.r,speed:s.speed,hp,maxHP:hp,ally,cd:0.2,skillCD:0,target:null,threat:{},lureUntil:0,active:false,status:'待命',color:COLORS[role],face:0,...(!ally?{range:s.range,damage:s.damage,interval:s.interval}:{})};}
    addPack(x,y,roles){const id=this.packs.length;const pack={id,active:false};this.packs.push(pack);roles.forEach((role,i)=>{let a=i*2.399,rr=30+Math.floor(i/3)*30;const e=this.unit(role,clamp(x+Math.cos(a)*rr,40,W-40),clamp(y+Math.sin(a)*rr,40,H-40));e.pack=id;this.enemies.push(e);});}
    log(message){this.logs.unshift({t:this.t,message});this.logs=this.logs.slice(0,24);}
    pulse(x,y,r,color,life=.55,kind='ring',label=''){this.fx.push({x,y,r,color,life,max:life,kind,label});}
    living(){return this.allies.filter(a=>a.hp>0);}
    engaged(){return this.enemies.filter(e=>e.hp>0&&e.active);}
    clearLine(a,b,pad=0){return !this.obstacles.some(o=>blocked(a,b,o,pad));}
    validPoint(p,r=18){return p.x>=r&&p.x<=W-r&&p.y>=r&&p.y<=H-r&&!this.obstacles.some(o=>p.x>o.x-r&&p.x<o.x+o.w+r&&p.y>o.y-r&&p.y<o.y+o.h+r);}
    // 路径绕过墙体，保持真实位置与攻击视线一致；最多两个静态障碍。
    waypoint(u,dest){
      if(this.clearLine(u,dest,u.r+2))return dest;
      const pad=u.r+5, nodes=[u,dest];
      for(const o of this.obstacles)for(const x of [o.x-pad,o.x+o.w+pad])for(const y of [o.y-pad,o.y+o.h+pad])nodes.push({x,y});
      const costs=nodes.map(()=>Infinity),prev=[],visited=new Set();costs[0]=0;
      for(let n=0;n<nodes.length;n++){
        let i=-1;for(let j=0;j<nodes.length;j++)if(!visited.has(j)&&(i<0||costs[j]<costs[i]))i=j;
        if(i<0||costs[i]===Infinity)break;if(i===1)break;visited.add(i);
        for(let j=1;j<nodes.length;j++)if(!visited.has(j)&&this.clearLine(nodes[i],nodes[j],u.r+2)){const c=costs[i]+dist(nodes[i],nodes[j]);if(c<costs[j]){costs[j]=c;prev[j]=i;}}
      }
      if(!Number.isFinite(costs[1]))return u;
      let k=1;while(prev[k]!==0&&prev[k]!==undefined)k=prev[k];return nodes[k];
    }
    move(u,p,dt,mult=1){
      if(!p)return;const to=this.waypoint(u,p),d=dist(u,to);if(d<2)return;
      const step=Math.min(d,u.speed*dt*mult),dx=(to.x-u.x)/d*step,dy=(to.y-u.y)/d*step;u.face=Math.atan2(dy,dx);
      if(this.validPoint({x:u.x+dx,y:u.y},u.r))u.x+=dx;
      if(this.validPoint({x:u.x,y:u.y+dy},u.r))u.y+=dy;
    }
    activate(e,source=this.hero){if(e.active)return;const pack=this.packs[e.pack];pack.active=true;for(const member of this.enemies.filter(x=>x.pack===e.pack&&x.hp>0)){member.active=true;member.threat[source.id]=(member.threat[source.id]||0)+25;member.target=source;}this.log(`敌群 ${e.pack+1} 加入战斗`);}
    // 仇恨由常规池 + 先锋限时贡献组成；不锁目标，不改射程，无特殊权级。
    threatValue(e,a){return (e.threat[a.id]||0)+(a===this.hero&&e.lureUntil>this.t?8000:0);}
    chooseEnemyTarget(e){let best=null,val=-1;for(const a of this.living()){const score=this.threatValue(e,a);if(score>val){best=a;val=score;}}if(e.target?.hp>0&&best!==e.target&&val<this.threatValue(e,e.target)*1.1)best=e.target;e.target=best;return best;}
    taunt(){if(this.state!=='playing'||this.hero.hp<=0||this.tauntCD>0)return false;let n=0;for(const e of this.enemies.filter(e=>e.hp>0&&dist(e,this.hero)<=180&&this.clearLine(e,this.hero))){this.activate(e);e.lureUntil=this.t+5;n++;}if(!n){this.log('挑衅范围内没有敌人（180 像素，需要视线）');return false;}this.tauntCD=8;this.metrics.taunts++;this.pulse(this.hero.x,this.hero.y,180,COLORS.hero,.7);this.log(`先锋接管 ${n} 个目标的仇恨，5 秒后释放`);return true;}
    // p 为世界坐标，合法地面才接受；null 表示恢复跟随。
    setAnchor(p){if(this.state!=='playing'||(p&&!this.validPoint(p,25)))return false;this.anchor=p?{...p}:null;this.metrics.moves++;this.log(p?'交战位置已更新；坦克接怪，远程与治疗保持距离':'队伍恢复跟随先锋');return true;}
    setMark(enemy){if(this.state!=='playing')return;this.mark=enemy&&enemy.hp>0?enemy:null;if(this.mark){this.metrics.marks++;this.log(`优先击杀：${enemy.name}。坦克与治疗保持职责。`);}else this.log('取消优先目标');}
    // 只读预览：按真实射程、视线与存活状态反馈参与者；不消耗资源。
    burstPreview(p){const attackers=this.allies.filter(a=>a.hp>0&&['caster','archer'].includes(a.role));const ready=attackers.filter(a=>dist(a,p)<=400&&this.clearLine(a,p));const targets=this.enemies.filter(e=>e.hp>0&&dist(e,p)<=135);let reason='';if(this.state!=='playing')reason='战斗已结束';else if(!this.validPoint(p,2))reason='请选择有效地面';else if(this.focus<45)reason='需要 45 点专注';else if(this.burstCD>0)reason=`爆发恢复中 ${this.burstCD.toFixed(1)} 秒`;else if(!ready.length)reason='没有输出角色能攻击此处（射程或视线受阻）';else if(!targets.length)reason='范围内没有敌人';return {ready,targets,valid:!reason,reason};}
    burst(p){const preview=this.burstPreview(p);if(!preview.valid){this.log(preview.reason);return false;}this.focus-=45;this.burstCD=16;this.lastBurst=this.t;this.metrics.bursts++;this.metrics.burstTimes.push(this.t);this.pulse(p.x,p.y,135,'#fff1b0',1,'target');for(const e of preview.targets)this.activate(e,preview.ready[0]);for(const a of preview.ready){a.status='集中爆发';a.cd=2;if(a.role==='caster')this.queue.push({at:this.t+.5,kind:'nova',actor:a,p:{...p}});else for(let i=0;i<3;i++)this.queue.push({at:this.t+.3+i*.24,kind:'volley',actor:a,p:{...p}});}this.log(`集中爆发：${preview.ready.map(a=>a.name).join(' + ')}，落点覆盖 ${preview.targets.length} 个目标`);return true;}
    hurt(target,amount,source,burst=false){if(target.hp<=0||amount<=0)return;const actual=Math.min(target.hp,amount);target.hp-=actual;this.pulse(target.x,target.y-18,0,burst?'#fff0b3':target.ally?'#ff9a9a':'#f0d7bf',.7,'text',String(Math.round(actual)));
      if(!target.ally){this.metrics.damage+=actual;if(burst)this.metrics.burstDamage+=actual;else this.focus=clamp(this.focus+actual*.025,0,100);if(source){this.activate(target,source);target.threat[source.id]=(target.threat[source.id]||0)+actual*(source.role==='guardian'?3:1);}if(target.hp<=0){this.metrics.kills++;if(burst)this.metrics.burstKills++;else this.focus=clamp(this.focus+5,0,100);this.pulse(target.x,target.y,22,target.color,.55,'death');if(this.mark===target)this.mark=null;if(target.role==='elite')this.log('光环精英倒下：附近敌人的伤害强化解除');}}
      else if(target.hp<=0){target.status='倒下';this.log(`${target.name} 倒下`);this.pulse(target.x,target.y,30,'#f46d81',.8,'death');}
    }
    heal(a,amount,source){if(a.hp<=0)return;const actual=Math.min(amount,a.maxHP-a.hp);if(actual<=0)return;a.hp+=actual;this.metrics.healed+=actual;this.pulse(a.x,a.y-20,0,'#a5efb5',.8,'text','+'+Math.round(actual));this.fx.push({x:source.x,y:source.y,to:{x:a.x,y:a.y},life:.3,max:.3,color:'#8ee6ad',kind:'line'});for(const e of this.engaged())e.threat[source.id]=(e.threat[source.id]||0)+actual*.12;}
    shoot(source,target,damage,burst=false,splash=0){this.projectiles.push({x:source.x,y:source.y,target,source,damage,burst,splash,speed:source.ally?440:250,life:4,color:source.color});}
    processQueue(){const due=this.queue.filter(q=>q.at<=this.t);this.queue=this.queue.filter(q=>q.at>this.t);for(const q of due){if(q.kind==='reinforce'){this.addPack(q.x,q.y,q.roles);this.log('东侧出现援军：可转移阵地或继续接战');this.pulse(q.x,q.y,95,'#ed9b73',2,'target');continue;}if(q.actor.hp<=0)continue;if(q.kind==='nova'){if(dist(q.actor,q.p)>430||!this.clearLine(q.actor,q.p)){this.log('Caster 爆发落点失去射程或视线');continue;}this.fx.push({x:q.actor.x,y:q.actor.y,to:q.p,kind:'line',color:q.actor.color,life:.35,max:.35});this.pulse(q.p.x,q.p.y,135,'#c7a0ff',.8,'nova');for(const e of this.enemies.filter(e=>e.hp>0&&dist(e,q.p)<=135&&this.clearLine(q.p,e)))this.hurt(e,92*this.settings.damageScale,q.actor,true);}else {const targets=this.enemies.filter(e=>e.hp>0&&dist(e,q.p)<=150&&dist(e,q.actor)<=420&&this.clearLine(q.actor,e));targets.sort((a,b)=>(a===this.mark?-1:b===this.mark?1:a.hp-b.hp));if(targets[0])this.shoot(q.actor,targets[0],66*this.settings.damageScale,true);}}}
    homeFor(a){const center=this.anchor||this.hero;const offset={guardian:[45,0],priest:[-75,-45],caster:[-60,60],archer:[-25,105]}[a.role]||[0,0];let p={x:clamp(center.x+offset[0],35,W-35),y:clamp(center.y+offset[1],35,H-35)};return this.validPoint(p,a.r)?p:center;}
    allyAI(a,dt){
      if(a===this.hero){a.status='玩家控制';return;}
      const home=this.homeFor(a),active=this.engaged(),near=active.filter(e=>dist(e,home)<310),inCombat=active.length>0;
      if(a.role==='priest'){
        const candidates=this.living().filter(x=>dist(x,a)<330&&this.clearLine(a,x)).sort((x,y)=>x.hp/x.maxHP-y.hp/y.maxHP),patient=candidates[0];
        if(patient&&patient.hp/patient.maxHP<.4&&a.skillCD<=0){this.heal(patient,150,a);a.skillCD=15;a.cd=1.3;this.pulse(patient.x,patient.y,35,'#96e596',.6);a.status='大治疗';}
        else if(patient&&patient.hp<patient.maxHP-8&&a.cd<=0){this.heal(patient,32,a);a.cd=1.7;a.status='治疗 '+patient.name;}
        else a.status=inCombat?'维持血线':'跟随';
        this.move(a,home,dt);return;
      }
      if(a.role==='guardian'){
        const nearby=active.filter(e=>dist(e,a)<135&&this.clearLine(a,e));
        if(a.skillCD<=0&&nearby.some(e=>e.target!==a)) {for(const e of nearby)e.threat[a.id]=(e.threat[a.id]||0)+650;a.skillCD=12;this.pulse(a.x,a.y,135,a.color,.55);this.log(`Guardian 嘲讽 ${nearby.length} 个敌人（常规仇恨入池）`);}
      }
      let target=null;
      if(a.role!=='guardian'&&this.mark?.hp>0&&dist(this.mark,home)<390)target=this.mark;
      if(!target)target=near.sort((x,y)=>{if(a.role==='guardian'){const sx=x.target!==a?-90:0,sy=y.target!==a?-90:0;return dist(a,x)+sx-dist(a,y)-sy;}return dist(a,x)-dist(a,y);})[0];
      a.target=target;const range=a.role==='guardian'?35:a.role==='caster'?300:325;
      if(target){const d=dist(a,target);if(d>range||!this.clearLine(a,target)){this.move(a,target,dt);a.status='接近目标';}else{
        if(a.cd<=0){if(a.role==='guardian'){this.hurt(target,13,a);a.cd=1.15;this.pulse(target.x,target.y,20,a.color,.2);}else{this.shoot(a,target,a.role==='caster'?18:17,false,a.role==='caster'?48:0);a.cd=a.role==='caster'?1.9:1.1;}a.status=target===this.mark?'优先击杀':'自动输出';}
        if(a.role!=='guardian'&&d<105){const dx=a.x-target.x,dy=a.y-target.y,l=Math.hypot(dx,dy)||1;this.move(a,{x:clamp(a.x+dx/l*40,25,W-25),y:clamp(a.y+dy/l*40,25,H-25)},dt);}else if(a.role!=='guardian'&&dist(a,home)>55)this.move(a,home,dt,.4);
      }}else{this.move(a,home,dt);a.status=this.anchor?'守住阵地':'跟随先锋';}
    }
    enemyAI(e,dt){if(!e.active){const seen=this.living().find(a=>dist(a,e)<125&&this.clearLine(e,a));if(seen)this.activate(e,seen);else return;}for(const id in e.threat)e.threat[id]*=Math.pow(.5,dt/14);const target=this.chooseEnemyTarget(e);if(!target)return;
      const d=dist(e,target);if(d>e.range+target.r||!this.clearLine(e,target)){this.move(e,target,dt);e.status='追击';}else{e.status='攻击';if(e.cd<=0){const empowered=this.enemies.some(x=>x.hp>0&&x.active&&x.role==='elite'&&x!==e&&dist(x,e)<155),amount=e.damage*(empowered?1.3:1);if(e.role==='melee'||e.role==='elite'){this.hurt(target,amount,e);this.pulse(target.x,target.y,18,e.color,.2);}else this.shoot(e,target,amount);e.cd=e.interval;}}
      if(e.role==='mage'&&e.skillCD<=0&&d<340){this.zones.push({x:target.x,y:target.y,r:66,remaining:1.6,max:1.6,source:e});e.skillCD=7;this.log('紫色危险区域即将落雷：可走位或转移阵地');}
    }
    separate(){const units=[...this.living(),...this.enemies.filter(e=>e.hp>0)];for(let i=0;i<units.length;i++)for(let j=i+1;j<units.length;j++){const a=units[i],b=units[j],d=dist(a,b),min=(a.r+b.r)*.85;if(d<min&&d>.01){const overlap=Math.min((min-d)*.3,2),dx=(a.x-b.x)/d*overlap,dy=(a.y-b.y)/d*overlap;for(const [u,sign] of [[a,1],[b,-1]]){if(u===this.hero)continue;const p={x:u.x+dx*sign,y:u.y+dy*sign};if(this.validPoint(p,u.r)){u.x=p.x;u.y=p.y;}}}}}
    // dt 为游戏时间增量（0..0.05）；input 是归一化前的玩家移动轴。
    step(dt,input={x:0,y:0}){
      if(this.state!=='playing')return;dt=clamp(dt,0,.05);this.t+=dt;this.tauntCD=Math.max(0,this.tauntCD-dt);this.burstCD=Math.max(0,this.burstCD-dt);
      if(this.hero.hp>0){const len=Math.hypot(input.x,input.y);if(len){this.move(this.hero,{x:clamp(this.hero.x+input.x/len*30,14,W-14),y:clamp(this.hero.y+input.y/len*30,14,H-14)},dt);this.noAction=0;}else{this.noAction+=dt;if(this.engaged().length)this.metrics.idle+=dt;}}
      this.processQueue();for(const u of [...this.allies,...this.enemies]){if(u.hp<=0)continue;u.cd=Math.max(0,u.cd-dt);u.skillCD=Math.max(0,u.skillCD-dt);if(u.ally)this.allyAI(u,dt);else this.enemyAI(u,dt);}this.separate();
      for(const p of this.projectiles){p.life-=dt;if(p.target.hp<=0){p.life=0;continue;}const d=dist(p,p.target),step=p.speed*dt,old={x:p.x,y:p.y};if(d<=step+p.target.r){if(!this.clearLine(old,p.target)){p.life=0;continue;}this.hurt(p.target,p.damage,p.source,p.burst);if(p.splash)for(const e of this.enemies.filter(e=>e.hp>0&&e!==p.target&&dist(e,p.target)<p.splash&&this.clearLine(p.target,e)))this.hurt(e,p.damage*.45,p.source,p.burst);p.life=0;}else{p.x+=(p.target.x-p.x)/d*step;p.y+=(p.target.y-p.y)/d*step;if(!this.clearLine(old,p))p.life=0;}}
      this.projectiles=this.projectiles.filter(p=>p.life>0);
      for(const z of this.zones){z.remaining-=dt;if(z.remaining<=0){if(z.source.hp>0){for(const a of this.living().filter(a=>dist(a,z)<=z.r))this.hurt(a,46,z.source);this.pulse(z.x,z.y,z.r,'#e098ed',.5,'nova');}}}this.zones=this.zones.filter(z=>z.remaining>0&&z.source.hp>0);
      for(const f of this.fx)f.life-=dt;this.fx=this.fx.filter(f=>f.life>0);
      if(this.enemies.every(e=>e.hp<=0)&&!this.queue.some(q=>q.kind==='reinforce')){this.state='won';this.log('战场清理完成');}
      else if(!this.living().some(a=>['guardian','caster','archer'].includes(a.role))){this.state='lost';this.endReason=this.living().length?'所有具有攻击能力的队友倒下，先锋与牧师无法继续清场':'队伍全灭';this.log(this.endReason);}
    }
  }
  const api={World,W,H,COLORS,dist,clamp};if(typeof module!=='undefined'&&module.exports)module.exports=api;else root.SquadSim=api;
})(typeof globalThis!=='undefined'?globalThis:this);
