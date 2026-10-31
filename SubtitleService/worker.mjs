const headers = {'Cache-Control':'no-store','Access-Control-Allow-Origin':'*','X-Content-Type-Options':'nosniff','Referrer-Policy':'no-referrer'};
const json = (value,status=200) => new Response(JSON.stringify(value),{status,headers:{...headers,'Content-Type':'application/json'}});
async function equal(a,b) {
  const hash = s => crypto.subtle.digest('SHA-256',new TextEncoder().encode(s));
  const [x,y] = await Promise.all([hash(a),hash(b)]);
  const u = new Uint8Array(x), v = new Uint8Array(y); let n=0;
  for(let i=0;i<u.length;i++) n|=u[i]^v[i]; return n===0;
}
export default {
  async fetch(request,env) {
    const url=new URL(request.url);
    if(request.method==='OPTIONS') return new Response(null,{status:204,headers:{...headers,'Access-Control-Allow-Methods':'GET, POST, OPTIONS','Access-Control-Allow-Headers':'Authorization, Content-Type'}});
    if(!env.DB||!env.UPLOAD_TOKEN) return json({error:'SERVICE_NOT_CONFIGURED'},503);
    if(url.pathname==='/subtitles'&&request.method==='POST') {
      if(!await equal(request.headers.get('Authorization')||'',`Bearer ${env.UPLOAD_TOKEN}`)) return json({error:'UNAUTHORIZED'},401);
      if(!request.headers.get('Content-Type')?.startsWith('text/vtt')) return json({error:'VTT_REQUIRED'},415);
      const reader=request.body?.getReader(); if(!reader) return json({error:'EMPTY'},400);
      let size=0; const chunks=[];
      try { while(true){const {value,done}=await reader.read();if(done)break;size+=value.length;if(size>1_000_000)return json({error:'TOO_LARGE'},413);chunks.push(value);} }
      finally {await reader.cancel().catch(()=>{});}
      const data=new Uint8Array(size);let offset=0;for(const c of chunks){data.set(c,offset);offset+=c.length;}
      const text=new TextDecoder('utf-8',{fatal:true}).decode(data);
      if(!text.startsWith('WEBVTT\n')||!text.includes('-->')||text.includes('\0'))return json({error:'INVALID_VTT'},400);
      const now=Math.floor(Date.now()/1000),expires=now+86400;
      // Shared service cap is enforced by the INSERT itself to avoid concurrent
      // uploads racing a separate count query. Expired objects are removed.
      await env.DB.prepare('DELETE FROM captions WHERE expires <= ?').bind(now).run();
      const id=Array.from(crypto.getRandomValues(new Uint8Array(32)),b=>b.toString(16).padStart(2,'0')).join('');
      const result=await env.DB.prepare('INSERT INTO captions (id, text, expires) SELECT ?, ?, ? WHERE (SELECT COUNT(*) FROM captions) < 100').bind(id,text,expires).run();
      if(result.meta.changes!==1)return json({error:'CAPACITY'},429);
      return json({url:`${url.origin}/vtt/${id}.vtt`,expires},201);
    }
    const match=url.pathname.match(/^\/vtt\/([a-f0-9]{64})\.vtt$/);
    if(match&&request.method==='GET') {
      const item=await env.DB.prepare('SELECT text FROM captions WHERE id = ? AND expires > ?').bind(match[1],Math.floor(Date.now()/1000)).first();
      if(!item)return json({error:'EXPIRED_OR_MISSING'},404);
      return new Response(item.text,{headers:{...headers,'Content-Type':'text/vtt; charset=utf-8'}});
    }
    return json({error:'NOT_FOUND'},404);
  }
};
