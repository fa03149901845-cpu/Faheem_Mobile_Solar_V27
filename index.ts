// V25 fail-closed payment webhook bridge. Provider-specific live signing must be configured before settlement.
import { serve } from 'https://deno.land/std@0.224.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
const db=createClient(Deno.env.get('SUPABASE_URL')!,Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
type V={valid:boolean;eventId:string;orderId?:string;status?:string;amount?:number;currency?:string;reason?:string};
async function verify(provider:string,payload:any,req:Request):Promise<V>{
 const id=String(payload?.pp_TxnRefNo||payload?.transactionId||payload?.transaction_id||payload?.event_id||crypto.randomUUID());
 if(provider==='jazzcash'){
  const secret=Deno.env.get('JAZZCASH_INTEGRITY_SALT'); const sig=String(payload?.pp_SecureHash||req.headers.get('x-jazzcash-signature')||'');
  if(!secret||!sig) return {valid:false,eventId:id,reason:'JazzCash signing secret/signature is not configured.'};
  return {valid:false,eventId:id,reason:'JazzCash merchant-specific secure-hash field ordering/algorithm must be configured from the current merchant contract.'};
 }
 if(provider==='easypaisa'){
  const secret=Deno.env.get('EASYPAISA_WEBHOOK_SECRET'); const sig=String(req.headers.get('x-easypaisa-signature')||payload?.signature||'');
  if(!secret||!sig) return {valid:false,eventId:id,reason:'Easypaisa signing secret/signature is not configured.'};
  return {valid:false,eventId:id,reason:'Easypaisa merchant-specific webhook signing contract must be configured before live settlement.'};
 }
 return {valid:false,eventId:id,reason:'Unsupported payment provider.'};
}
serve(async(req)=>{
 if(req.method!=='POST') return new Response('Method Not Allowed',{status:405});
 const provider=(new URL(req.url).searchParams.get('provider')||'').toLowerCase();
 if(!provider) return Response.json({ok:false,error:'provider is required'},{status:400});
 const raw=await req.text(); let payload:any; try{payload=JSON.parse(raw)}catch{payload={raw}};
 const v=await verify(provider,payload,req); const eventType=String(payload?.event_type||payload?.status||payload?.transaction_status||'unknown');
 const {data:event,error}=await db.from('payment_webhook_events').upsert({provider,event_type:eventType,provider_event_id:v.eventId,signature_valid:v.valid,payload},{onConflict:'provider,provider_event_id',ignoreDuplicates:false}).select('id').single();
 if(error) return Response.json({ok:false,error:error.message},{status:500});
 if(!v.valid) return Response.json({ok:true,processed:false,event_id:event.id,reason:v.reason},{status:202});
 if(!v.orderId||typeof v.amount!=='number'||!v.currency) return Response.json({ok:true,processed:false,event_id:event.id,reason:'Verified event missing authoritative order/amount/currency mapping'},{status:202});
 const {data:order,error:oe}=await db.from('orders').select('id,total,payment_status').eq('id',v.orderId).single();
 if(oe||!order) return Response.json({ok:true,processed:false,event_id:event.id,reason:'Order not found'},{status:202});
 if(Number(order.total)!==Number(v.amount)||String(v.currency).toUpperCase()!=='PKR') return Response.json({ok:true,processed:false,event_id:event.id,reason:'Amount/currency mismatch'},{status:202});
 const success=['paid','success','successful','completed'].includes(String(v.status||eventType).toLowerCase());
 if(!success) return Response.json({ok:true,processed:false,event_id:event.id,reason:'Not a confirmed successful payment'});
 const {error:ue}=await db.from('orders').update({payment_status:'verified'}).eq('id',v.orderId).neq('payment_status','verified');
 if(ue) return Response.json({ok:false,error:ue.message},{status:500});
 return Response.json({ok:true,processed:true,event_id:event.id,order_id:v.orderId,payment_status:'verified'});
});
