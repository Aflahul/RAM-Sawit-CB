require('dotenv').config({ path: '.env.local' });
const { createClient } = require('@supabase/supabase-js');

const supabase = createClient(process.env.NEXT_PUBLIC_SUPABASE_URL, process.env.SUPABASE_SERVICE_ROLE_KEY || process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY);

const updates = [
  { kode: 'SL', nominal: 800000, angkut: 150 },
  { kode: 'BL', nominal: 750000, angkut: 150 },
  { kode: 'SL/F', nominal: 750000, angkut: 150 },
  { kode: 'SL/BS', nominal: 750000, angkut: 150 },
  { kode: 'SL/MLD', nominal: 750000, angkut: 150 },
  { kode: 'BL/ML', nominal: 900000, angkut: 180 },
];

async function run() {
  for (const { kode, nominal, angkut } of updates) {
    console.log(`Updating ${kode}...`);
    // Cari master_mitra by kode (case insensitive)
    const { data: mitras } = await supabase.from('master_mitra').select('id, kode').ilike('kode', kode);
    if (!mitras || mitras.length === 0) {
      console.log(`Mitra ${kode} not found!`);
      continue;
    }
    const id = mitras[0].id;
    
    // Update master_mitra
    await supabase.from('master_mitra').update({
      nominal_perongkosan: nominal,
      tarif_sewa_angkut_per_kg: angkut
    }).eq('id', id);
    
    // Update active history
    await supabase.from('fee_owner_mitra_history').update({
      nominal_perongkosan: nominal,
      tarif_sewa_angkut_per_kg: angkut
    }).eq('master_mitra_id', id).eq('aktif', true);
    
    console.log(`Updated ${kode} successfully!`);
  }
}

run().catch(console.error);
