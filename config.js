export default function handler(req,res){
  res.setHeader('Cache-Control','no-store');
  const supabaseUrl=process.env.SUPABASE_URL||process.env.NEXT_PUBLIC_SUPABASE_URL||process.env.VITE_SUPABASE_URL||'';
  const supabaseKey=process.env.SUPABASE_PUBLISHABLE_KEY||process.env.SUPABASE_ANON_KEY||process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY||process.env.VITE_SUPABASE_ANON_KEY||'';
  if(!supabaseUrl||!supabaseKey)return res.status(404).json({configured:false});
  return res.status(200).json({configured:true,supabaseUrl,supabaseKey});
}
