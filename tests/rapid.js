const fs=require("fs");const path=require("path");
let JSDOM; try{({JSDOM}=require("jsdom"))}catch(e){for(const p of["/tmp/atlastest/node_modules/jsdom","/tmp/atlas-test/node_modules/jsdom"]){try{({JSDOM}=require(p));break}catch(_){}} if(!JSDOM){console.error("需要 jsdom");process.exit(2)}}
const html=fs.readFileSync(path.join(__dirname,"..","src","index.html"),"utf8");
const sleep=ms=>new Promise(r=>setTimeout(r,ms));
(async()=>{
  const dom=new JSDOM(html,{url:"http://localhost/",runScripts:"dangerously",pretendToBeVisual:true,beforeParse(w){w.fetch=()=>Promise.resolve({ok:true,status:200,text:()=>Promise.resolve("{}")});w.URL.createObjectURL=()=>"blob:x"}});
  const win=dom.window,doc=win.document;await sleep(60);
  doc.querySelectorAll(".tabbtn").forEach((b,i)=>{Object.defineProperty(b,"offsetLeft",{configurable:true,get:()=>7+i*70});Object.defineProperty(b,"offsetWidth",{configurable:true,get:()=>66})});
  win.dispatchEvent(new win.Event("resize"));await sleep(20);
  const btns=doc.querySelectorAll(".tabbtn"),lens=doc.getElementById("tabLens");
  btns[3].click();await sleep(50);btns[1].click();await sleep(50);btns[2].click(); // 快速连点，最后目标=第3个
  await sleep(500);
  console.log("final transform:",lens.style.transform);
  console.log(lens.style.transform.includes("translateX(147px)")&&lens.style.transform.includes("scaleX(1)")?"RAPID_OK":"RAPID_FAIL");
  console.log("on class:",doc.querySelector(".tabbtn.on").dataset.view);
  win.close();
})();
