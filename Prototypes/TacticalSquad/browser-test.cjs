// 运行：node browser-test.cjs <playwright包目录>。先启动 serve.cjs。
const {chromium}=require(process.argv[2]||'playwright');
const assert=require('node:assert/strict');
(async()=>{
  const browser=await chromium.launch({headless:true,channel:'msedge'});
  const page=await browser.newPage({viewport:{width:1500,height:1000}}),errors=[];
  page.on('pageerror',e=>errors.push(e.message));
  await page.goto('http://127.0.0.1:8765');await page.getByRole('button',{name:'进入战场',exact:true}).click();
  await page.keyboard.down('KeyD');await page.waitForTimeout(1300);await page.keyboard.up('KeyD');
  let s=await page.evaluate(()=>window.prototypeSnapshot());assert.ok(s.hero.x>350);assert.equal(s.allies.length,5);
  const box=await page.locator('canvas').boundingBox();
  const move=async(x,y)=>page.mouse.move(box.x+x/1200*box.width,box.y+y/740*box.height);
  await move(400,370);await page.keyboard.press('KeyE');
  await page.keyboard.down('KeyD');await page.waitForTimeout(650);await page.keyboard.up('KeyD');await page.keyboard.press('KeyQ');
  await page.keyboard.down('KeyA');await page.waitForTimeout(750);await page.keyboard.up('KeyA');
  await page.waitForTimeout(500);await move(540,370);await page.keyboard.press('Tab');
  s=await page.evaluate(()=>window.prototypeSnapshot());assert.equal(s.mode,'burst');const focus=s.focus;
  await page.screenshot({path:__dirname+'/preview.png',fullPage:true});
  await page.keyboard.press('Escape');s=await page.evaluate(()=>window.prototypeSnapshot());assert.equal(s.mode,'normal');assert.ok(s.focus>=focus);
  await page.keyboard.press('Space');const before=await page.evaluate(()=>window.prototypeSnapshot().time);await page.waitForTimeout(250);assert.equal(await page.evaluate(()=>window.prototypeSnapshot().time),before);await page.keyboard.press('Space');
  await page.keyboard.press('Tab');await move(500,370);await page.mouse.click(box.x+500/1200*box.width,box.y+370/740*box.height);await page.waitForTimeout(1000);
  s=await page.evaluate(()=>window.prototypeSnapshot());assert.ok(s.metrics.bursts>=1,'a valid preview must execute a real burst');
  await page.getByRole('button',{name:'重试本局',exact:true}).click();s=await page.evaluate(()=>window.prototypeSnapshot());assert.equal(s.metrics.bursts,0);assert.equal(s.enemies.length,15);
  await page.locator('#scenario').selectOption('skirmish');await page.getByRole('button',{name:'应用设置并重新开始',exact:true}).click();s=await page.evaluate(()=>window.prototypeSnapshot());assert.equal(s.enemies.length,6);
  await page.getByRole('button',{name:'操作说明',exact:true}).click();assert.equal(await page.locator('#overlay').isVisible(),true);await page.getByRole('button',{name:'返回战场',exact:true}).click();
  assert.deepEqual(errors,[]);console.log('BROWSER PASS: movement, rally, taunt, slow-time, cancellation, burst, pause, restart, preset and help; no page errors');
  await browser.close();
})().catch(e=>{console.error(e);process.exit(1);});
