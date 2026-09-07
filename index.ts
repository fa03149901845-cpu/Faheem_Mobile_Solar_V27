// V25 WhatsApp Cloud API worker + Meta webhook verification handshake.
import { serve } from 'https://deno.land/std@0.224.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
const db=createClient(Deno.env.get('SUPABASE_URL')!,Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const token=Deno.env.get('WHATSAPP_ACCESS_TOKEN'); const phoneNumberId=Deno.env.get('WHATSAPP_PHONE_NUMBER_ID'); const graphVersion=Deno.env.get('WHATSAPP_GRAPH_VERSION')||'v23.0';
function verify(req:Request){const u=new URL(req.url),expected=Deno.env.get('WHATSAPP_VERIFY_TOKEN');if(u.searchParams.get('hub.mode')==='subscribe'&&expected&&u.searchParams.get('hub.verify_token')===expected&&u.searchParams.get('hub.challenge'))return new Response(u.searchParams.get('hub.challenge')!,{status:200});return new Response('Forbidden',{status:403});}
serve(async(req)=>{
 if(req.method==='GET') return verify(req);
 if(req.method!=='POST') return new Response('Method Not Allowed',{status:405});
 if(!token||!phoneNumberId) return Response.json({ok:false,configured:false,message:'WhatsApp secrets are not configured.'},{status:503});
 const {data:msg,error:claimError}=await db.rpc('claim_whatsapp_message'); if(claimError)return Response.json({ok:false,error:claimError.message},{status:500}); if(!msg)return Response.json({ok:true,queued:false,message:'No queued WhatsApp messages.'});
 try{const endpoint=`https://graph.facebook.com/${graphVersion}/${phoneNumberId}/messages`;const body={messaging_product:'whatsapp',recipient_type:'individual',to:msg.recipient,type:'text',text:{preview_url:false,body:msg.message}};const r=await fetch(endpoint,{method:'POST',headers:{Authorization:`Bearer ${token}`,'Content-Type':'application/json'},body:JSON.stringify(body)});const data=await r.json().catch(()=>({}));if(!r.ok)throw new Error(`WhatsApp API ${r.status}: ${JSON.stringify(data).slice(0,800)}`);const pid=data?.messages?.[0]?.id||null;const {error}=await db.rpc('finish_whatsapp_message',{p_id:msg.id,p_success:true,p_provider_message_id:pid,p_error:null});if(error)throw error;return Response.json({ok:true,sent:true,message_id:msg.id,provider_message_id:pid});}catch(e){await db.rpc('finish_whatsapp_message',{p_id:msg.id,p_success:false,p_provider_message_id:null,p_error:String(e)});return Response.json({ok:false,sent:false,message_id:msg.id,error:String(e)},{status:502});}
});
