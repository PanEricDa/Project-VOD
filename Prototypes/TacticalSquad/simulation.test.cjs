const {test}=require('node:test');
const assert=require('node:assert/strict');
const {World,dist}=require('./simulation.js');
function emptyWorld(){const w=new World({scenario:'skirmish'});w.enemies=[];w.packs=[];w.queue=[];return w;}
test('five-person party, scenario populations and delayed reinforcement',()=>{
  for(const [scenario,total] of [['skirmish',6],['mixed',15],['endurance',20]]){const w=new World({scenario});assert.equal(w.allies.length,5);assert.equal(w.total,total);}
  const w=new World({scenario:'endurance'});w.t=49;w.processQueue();assert.equal(w.enemies.length,20);assert.equal(w.queue.length,0);
});
test('temporary player threat expires; Guardian threat stays in ordinary pool',()=>{
  const w=emptyWorld();w.addPack(260,350,['melee']);const e=w.enemies[0],g=w.allies[1];assert.ok(w.taunt());e.threat[g.id]=650;assert.equal(w.chooseEnemyTarget(e),w.hero);w.t=5.1;assert.equal(w.chooseEnemyTarget(e),g);assert.equal(e.threat[g.id],650);
});
test('ranged enemy keeps its attack range under player taunt',()=>{
  const w=emptyWorld();w.addPack(260,350,['ranged']);const e=w.enemies[0];assert.ok(w.taunt());const p={x:e.x,y:e.y};w.enemyAI(e,.05);assert.equal(dist(e,p),0);assert.equal(e.target,w.hero);
});
test('blocked ground rejected; units can route around wall',()=>{
  const w=new World();assert.equal(w.setAnchor({x:490,y:180}),false);const a=w.allies[1];a.x=400;a.y=190;for(let i=0;i<250;i++)w.move(a,{x:600,y:190},.05);assert.ok(dist(a,{x:600,y:190})<5);assert.ok(w.validPoint(a,a.r));
});
test('burst preview does not mutate state; invalid commands do not spend focus',()=>{
  const w=new World(),initial=w.focus,count=w.queue.length;assert.equal(w.burstPreview({x:1170,y:50}).valid,false);assert.equal(w.focus,initial);assert.equal(w.queue.length,count);assert.equal(w.burst({x:1170,y:50}),false);assert.equal(w.focus,initial);
});
test('burst affects local targets only; dead casters cannot finish queued attacks',()=>{
  const w=emptyWorld();w.addPack(280,360,['melee']);w.addPack(900,360,['melee']);const near=w.enemies[0],far=w.enemies[1],old=far.hp;assert.equal(w.burst({x:near.x,y:near.y}),true);assert.equal(w.focus,35);w.t=1;w.processQueue();assert.ok(near.hp<near.maxHP);assert.equal(far.hp,old);assert.equal(w.focus,35);
  const v=emptyWorld();v.addPack(280,360,['melee']);const e=v.enemies[0];v.burst(e);for(const a of v.allies.filter(a=>['caster','archer'].includes(a.role)))a.hp=0;v.t=1;v.processQueue();assert.equal(e.hp,e.maxHP);assert.equal(v.projectiles.length,0);
});
test('focus gains require regular damage; no idle or burst refunds',()=>{
  const w=new World();w.focus=20;for(let i=0;i<200;i++)w.step(.05);assert.equal(w.focus,20);const e=w.enemies[0];w.hurt(e,20,w.allies[3],true);assert.equal(w.focus,20);w.hurt(e,20,w.allies[3],false);assert.ok(w.focus>20);
});
test('full-party defeat and final kill produce terminal states',()=>{
  const w=new World();for(const a of w.allies)a.hp=0;w.step(.05);assert.equal(w.state,'lost');const v=new World({scenario:'skirmish'});for(const e of v.enemies)e.hp=0;v.step(.05);assert.equal(v.state,'won');
});
test('priority marking alone creates no threat; noncombatant survivors cannot softlock',()=>{
  const w=new World();w.setMark(w.enemies[0]);assert.equal(w.enemies[0].active,false);for(const a of w.allies.filter(a=>['guardian','caster','archer'].includes(a.role)))a.hp=0;w.step(.05);assert.equal(w.state,'lost');assert.ok(w.endReason.includes('无法继续清场'));
});
test('deterministic 180-second tactical soak remains finite and progresses',()=>{
  const w=new World({scenario:'mixed'});w.setAnchor({x:600,y:370});
  for(let i=0;i<3600&&w.state==='playing';i++){
    const targets=w.enemies.filter(e=>e.hp>0),e=targets[0];if(!e)break;
    const d=dist(w.hero,e),input=d>100?{x:(e.x-w.hero.x)/d,y:(e.y-w.hero.y)/d}:{x:0,y:0};
    if(i%40===0){w.taunt();w.setMark(e);if(w.burstPreview(e).valid)w.burst(e);if(dist(e,w.anchor)>240)w.setAnchor({x:e.x-80,y:e.y});}w.step(.05,input);
    for(const u of [...w.allies,...w.enemies])assert.ok(Number.isFinite(u.x)&&Number.isFinite(u.y)&&u.hp>=0);
  }
  assert.ok(w.metrics.kills>0);assert.ok(w.metrics.bursts>0);console.log('SOAK',JSON.stringify({state:w.state,t:w.t,kills:w.metrics.kills,bursts:w.metrics.bursts,alive:w.living().length}));
});
