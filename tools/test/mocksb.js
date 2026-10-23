const http=require('http');
const U={tA:{id:'aaaaaaaa-0000-4000-8000-000000000001',username:'Alpha',pr:120},tB:{id:'bbbbbbbb-0000-4000-8000-000000000002',username:'Bravo',pr:330},tC:{id:'cccccccc-0000-4000-8000-000000000003',username:'Charlie',pr:40},tD:{id:'dddddddd-0000-4000-8000-000000000004',username:'Delta',pr:10}};
const byId=Object.fromEntries(Object.values(U).map(u=>[u.id,u]));
const pairs=[[U.tA.id,U.tB.id],[U.tA.id,U.tC.id]];
http.createServer((req,res)=>{ const url=new URL(req.url,'http://x'); const j=o=>{res.writeHead(200,{'Content-Type':'application/json'});res.end(JSON.stringify(o));};
 if(url.pathname==='/auth/v1/user'){ const t=(req.headers.authorization||'').replace('Bearer ',''); const u=U[t]; if(!u){res.writeHead(401);res.end('{}');return;} return j({id:u.id}); }
 if(url.pathname==='/rest/v1/profiles'){ const id=(url.searchParams.get('id')||'').replace('eq.',''); const u=byId[id]; return j(u?[{username:u.username,pr:u.pr}]:[]); }
 if(url.pathname==='/rest/v1/friendships'){ const m=(url.searchParams.get('or')||'').match(/requester\.eq\.([^,]+)/); const id=m&&m[1]; return j(pairs.filter(p=>p.includes(id)).map(p=>({requester:p[0],addressee:p[1]}))); }
 if(url.pathname==='/rest/v1/rpc/record_ranked_result'){ let b='';req.on('data',d=>b+=d);req.on('end',()=>j({pr_before:100,pr_delta:12,pr_after:112,rank:'Rookie II'})); return; }
 res.writeHead(404);res.end('{}');
}).listen(5599,()=>console.log('mock ok'));
