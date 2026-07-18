'use server';

import { createClient } from '@/utils/supabase/server';
import { createAdminClient } from '@/utils/supabase/admin';
import { canManageUsers } from '@/lib/roles';
import { revalidatePath } from 'next/cache';

async function verifySuperAdmin() {
  const supabase = await createClient();
  const { data: { session }, error: sessionError } = await supabase.auth.getSession();
  
  if (sessionError || !session?.user) {
    throw new Error('Unauthorized: No active session.');
  }

  const { data: userData, error: userError } = await supabase
    .from('users')
    .select('role')
    .eq('id', session.user.id)
    .single();

  if (userError || !userData) {
    throw new Error('Unauthorized: Profile not found.');
  }

  if (!canManageUsers(userData.role)) {
    throw new Error('Forbidden: Only Super Admin can perform this action.');
  }
}

export async function getUsersAction() {
  try {
    await verifySuperAdmin();
    const adminAuthClient = createAdminClient();

    // Fetch from auth.users
    const { data: authData, error: authError } = await adminAuthClient.auth.admin.listUsers();
    if (authError) throw authError;

    // Fetch from public.users
    const { data: dbData, error: dbError } = await adminAuthClient
      .from('users')
      .select('*')
      .order('nama');
    if (dbError) throw dbError;

    // Merge data
    const users = dbData.map(dbUser => {
      const authUser = authData.users.find(u => u.id === dbUser.id);
      return {
        ...dbUser,
        email: authUser?.email || 'Email tidak ditemukan',
      };
    });

    return { success: true, users };
  } catch (error) {
    console.error('getUsersAction error:', error);
    return { success: false, error: error.message || 'Gagal memuat pengguna' };
  }
}

export async function createUserAction(formData) {
  try {
    await verifySuperAdmin();

    const nama = formData.get('nama');
    const email = formData.get('email');
    const username = formData.get('username') || null;
    const password = formData.get('password');
    const role = formData.get('role');

    if (!nama || !email || !password || !role) {
      throw new Error('Semua kolom wajib (Nama, Email, Password, Role) harus diisi.');
    }

    const adminAuthClient = createAdminClient();

    // 1. Create in auth.users
    const { data: authData, error: authError } = await adminAuthClient.auth.admin.createUser({
      email,
      password,
      email_confirm: true,
    });

    if (authError) {
      throw new Error(`Gagal membuat otentikasi: ${authError.message}`);
    }

    const newUserId = authData.user.id;

    // 2. Insert into public.users
    const { error: dbError } = await adminAuthClient
      .from('users')
      .insert({
        id: newUserId,
        nama,
        username,
        role,
      });

    if (dbError) {
      // Rollback auth user creation if public profile fails
      await adminAuthClient.auth.admin.deleteUser(newUserId);
      throw new Error(`Gagal menyimpan profil pengguna: ${dbError.message}`);
    }

    revalidatePath('/superadmin/users');
    return { success: true, message: 'Pengguna berhasil dibuat.' };
  } catch (error) {
    console.error('createUserAction error:', error);
    return { success: false, error: error.message || 'Terjadi kesalahan internal.' };
  }
}

export async function updateUserAction(formData) {
  try {
    await verifySuperAdmin();

    const id = formData.get('id');
    const nama = formData.get('nama');
    const username = formData.get('username') || null;
    const role = formData.get('role');

    if (!id || !nama || !role) {
      throw new Error('ID, Nama, dan Role wajib diisi.');
    }

    const adminAuthClient = createAdminClient();

    const { error: dbError } = await adminAuthClient
      .from('users')
      .update({
        nama,
        username,
        role,
        updated_at: new Date().toISOString(),
      })
      .eq('id', id);

    if (dbError) {
      throw new Error(`Gagal memperbarui profil pengguna: ${dbError.message}`);
    }

    revalidatePath('/superadmin/users');
    return { success: true, message: 'Pengguna berhasil diperbarui.' };
  } catch (error) {
    console.error('updateUserAction error:', error);
    return { success: false, error: error.message || 'Terjadi kesalahan internal.' };
  }
}
