import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import vm from 'node:vm';
const source=await readFile(process.argv[2],'utf8');
class Element {
 constructor(tag,doc){this.tagName=tag;this.ownerDocument=doc;this.children=[];this.attributes={};this.listeners={};this.style={};this.isConnected=true;}
 appendChild(node){this.children.push(node);node.parentNode=this;return node;}
 insertBefore(node,reference){let i=this.children.indexOf(reference);if(i<0)i=this.children.length;this.children.splice(i,0,node);node.parentNode=this;return node;}
 get nextSibling(){const p=this.parentNode;if(!p)return null;return p.children[p.children.indexOf(this)+1]||null;}
 getAttribute(k){return this.attributes[k]??null;}
 setAttribute(k,v){this.attributes[k]=v;}
 addEventListener(k,fn){(this.listeners[k]||=[]).push(fn);}
 removeEventListener(k,fn){this.listeners[k]=(this.listeners[k]||[]).filter(x=>x!==fn);}
 fire(k){for(const fn of this.listeners[k]||[])fn({target:this});}
 remove(){this.isConnected=false;if(this.parentNode)this.parentNode.children=this.parentNode.children.filter(x=>x!==this);}
 focus(){}
}
function makeDoc(href){const d={location:{href},createElement:tag=>new Element(tag,d)};d.body=new Element('body',d);d.inputs=[];d.anchors=[];d.frames=[];d.querySelectorAll=selector=>selector==='input[type="file"]'?d.inputs:selector.startsWith('a[href]')?d.anchors:selector==='iframe,frame'?d.frames:[];return d;}
const top=makeDoc('https://gakujo.iess.niigata-u.ac.jp/campusweb/campusportal.do');
const child=makeDoc('https://gakujo.iess.niigata-u.ac.jp/campusweb/campussquare.do?_flowExecutionKey=synthetic');
const anchor=new Element('a',child);anchor.textContent='synthetic.pdf';anchor.attributes.href='javascript:void(0);';anchor.attributes.onclick="return callFileDownLoad('answerDownLoad', 1, 2, '')";child.body.appendChild(anchor);child.anchors.push(anchor);
const unsafe=new Element('a',child);unsafe.textContent='other.pdf';unsafe.attributes.href='javascript:void(0);';unsafe.attributes.onclick="return submit('delete')";child.body.appendChild(unsafe);child.anchors.push(unsafe);
const message=new Element('a',child);message.textContent='通知の資料.pdf';message.attributes.href='campussquare.do?_flowExecutionKey=synthetic&_eventId=download&keijitype=1&genrecd=40&seqNo=42&index=0';child.body.appendChild(message);child.anchors.push(message);
const direct=new Element('a',child);direct.textContent='授業資料.pdf';direct.attributes.href='../files/lecture.pdf';child.body.appendChild(direct);child.anchors.push(direct);
const workflow=new Element('a',child);workflow.textContent='確認';workflow.attributes.href='campussquare.do?_eventId=confirm&fileId=42';child.body.appendChild(workflow);child.anchors.push(workflow);
const external=new Element('a',child);external.textContent='外部.pdf';external.attributes.href='https://example.invalid/file.pdf';child.body.appendChild(external);child.anchors.push(external);
const download=new Element('button',child);download.textContent='ダウンロード';download.form={getAttribute:key=>({method:'POST',action:'campussquare.do'}[key]||null),fields:{_eventId:'download',fileId:'42'}};child.body.appendChild(download);child.anchors.push(download);
const submit=new Element('button',child);submit.textContent='提出';submit.form={getAttribute:key=>({method:'POST',action:'campussquare.do'}[key]||null),fields:{_eventId:'submit',fileId:'42'}};child.body.appendChild(submit);child.anchors.push(submit);
const ownPreview=new Element('button',child);ownPreview.textContent='プレビューを見る';ownPreview.form=download.form;ownPreview.attributes['data-mbg-submitted-preview']='true';child.body.appendChild(ownPreview);child.anchors.push(ownPreview);
const ownUpload=new Element('button',child);ownUpload.textContent='選択したファイルをプレビュー';ownUpload.form=download.form;ownUpload.attributes['data-mbg-upload-preview']='true';child.body.appendChild(ownUpload);child.anchors.push(ownUpload);
const frame={contentWindow:{document:child}};top.frames.push(frame);
const grandchild=makeDoc('https://gakujo.iess.niigata-u.ac.jp/campusweb/campussquare.do?_flowExecutionKey=nested');
const nested=new Element('a',grandchild);nested.textContent='nested.pdf';nested.attributes.href='campussquare.do?_eventId=download&fileId=3';grandchild.body.appendChild(nested);grandchild.anchors.push(nested);
child.frames.push({contentWindow:{document:grandchild}});
const window={document:top,location:{origin:'https://gakujo.iess.niigata-u.ac.jp',href:top.location.href},setInterval(fn){this.attach=fn;return 1;},clearInterval(){},addEventListener(){},removeEventListener(){}};
window.top=window;top.defaultView=window;child.defaultView={document:child,location:child.location,frameElement:{isConnected:true}};
class FormData { constructor(form){this.fields={...form.fields};} set(k,v){this.fields[k]=v;} forEach(fn){Object.entries(this.fields).forEach(([k,v])=>fn(v,k));} }
vm.runInNewContext(source,{window,document:top,URL,URLSearchParams,FormData,Uint8Array,DataView,ArrayBuffer,Promise,Math,Number,Error});
const button=anchor.__mbgSubmittedPreviewButton;
assert.ok(button,'submitted link gets a preview button');
assert.equal(button.textContent,'プレビューを見る');
assert.equal(unsafe.__mbgSubmittedPreviewButton,undefined,'other actions get no button');
assert.ok(message.__mbgSubmittedPreviewButton,'notification attachment gets a preview button');
assert.ok(direct.__mbgSubmittedPreviewButton,'direct attachment gets a preview button');
assert.equal(workflow.__mbgSubmittedPreviewButton,undefined,'workflow links do not get a preview button');
assert.equal(external.__mbgSubmittedPreviewButton,undefined,'external links do not get a preview button');
assert.ok(download.__mbgSubmittedPreviewButton,'safe attachment forms get a preview button');
assert.ok(nested.__mbgSubmittedPreviewButton,'nested frames also receive preview buttons');
assert.equal(submit.__mbgSubmittedPreviewButton,undefined,'submission forms do not get a preview button');
assert.equal(ownPreview.__mbgSubmittedPreviewButton,undefined,'preview controls in a download form do not create more controls');
assert.equal(ownUpload.__mbgSubmittedPreviewButton,undefined,'upload preview controls are not treated as download forms');
let requested;window.__MBG_OPEN_REMOTE_PREVIEW=req=>{requested=req;return true;};button.fire('click');
assert.equal(requested.method,'GET');assert.equal(requested.fileName,'synthetic.pdf');
const url=new URL(requested.url);assert.equal(url.origin,'https://gakujo.iess.niigata-u.ac.jp');
assert.equal(url.pathname,'/campusweb/campussquare.do');
for(const [k,v] of Object.entries({_flowExecutionKey:'synthetic',_eventId:'answerDownLoad',questionSort:'1',tempNo:'2',ansTempId:''}))assert.equal(url.searchParams.get(k),v);
assert.equal(anchor.getAttribute('href'),'javascript:void(0);');assert.equal(anchor.listeners.click,undefined,'original link behavior stays untouched');
message.__mbgSubmittedPreviewButton.fire('click');
assert.equal(new URL(requested.url).searchParams.get('_eventId'),'download');
assert.equal(requested.fileName,'通知の資料.pdf');
download.__mbgSubmittedPreviewButton.fire('click');
assert.equal(requested.method,'POST');assert.equal(requested.formFields.fileId,'42');
window.attach();assert.equal(child.body.children.filter(x=>x.textContent==='プレビューを見る').length,5,'repeated attachment does not duplicate controls');
child.location.href='https://evil.invalid/campusweb/campussquare.do?_flowExecutionKey=synthetic';requested=undefined;button.fire('click');assert.equal(requested,undefined,'navigated frames cannot issue a request');
console.log('Submitted preview button opens only the matching safe request.');
