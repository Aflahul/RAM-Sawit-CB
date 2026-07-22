'use client';

import { useCallback, useEffect, useMemo, useState } from 'react';
import AppShell from '@/components/layout/AppShell';
import SortableHeader from '@/components/ui/SortableHeader';
import TablePagination from '@/components/ui/TablePagination';
import { Pencil, Search, Users, X } from 'lucide-react';
import { paginateRows } from '@/lib/pagination-utils';
import { getNextSort, sortRows } from '@/lib/sort-utils';
import { getRoleLabel } from '@/lib/roles';
import {
  PASSWORD_HTML_PATTERN,
  PASSWORD_MIN_LENGTH,
  PASSWORD_REQUIREMENTS_MESSAGE,
} from '@/lib/password-policy.mjs';
import { createUserAction, updateUserAction, getUsersAction } from './actions';

const TABLE_PAGE_SIZE = 20;

const userSortAccessors = {
  nama: row => row.nama,
  email: row => row.email,
  username: row => row.username,
  role: row => getRoleLabel(row.role),
};

export default function UserManagementPage() {
  const [users, setUsers] = useState([]);
  const [loading, setLoading] = useState(true);
  const [showModal, setShowModal] = useState(false);
  const [editingId, setEditingId] = useState(null);
  const [saving, setSaving] = useState(false);
  const [search, setSearch] = useState('');
  const [sort, setSort] = useState({ key: 'nama', direction: 'asc' });
  const [page, setPage] = useState(1);
  const [toast, setToast] = useState(null);
  const [formUser, setFormUser] = useState({
    nama: '',
    email: '',
    username: '',
    password: '',
    role: 'admin_operasional',
  });

  const loadData = useCallback(async () => {
    setLoading(true);
    const res = await getUsersAction();
    if (res.success) {
      setUsers(res.users || []);
    } else {
      showToast(`Gagal memuat pengguna: ${res.error}`, 'error');
    }
    setLoading(false);
  }, []);

  useEffect(() => {
    // eslint-disable-next-line react-hooks/set-state-in-effect
    loadData();
  }, [loadData]);

  function showToast(message, type = 'success') {
    setToast({ message, type });
    setTimeout(() => setToast(null), 3000);
  }

  function resetForm() {
    setFormUser({
      nama: '',
      email: '',
      username: '',
      password: '',
      role: 'admin_operasional',
    });
    setEditingId(null);
  }

  function handleOpenModal(user = null) {
    if (user) {
      setFormUser({
        nama: user.nama || '',
        email: '',
        username: user.username || '',
        password: '',
        role: user.role,
      });
      setEditingId(user.id);
    } else {
      resetForm();
    }
    setShowModal(true);
  }

  async function handleSave(e) {
    e.preventDefault();
    setSaving(true);
    setToast(null);

    const formData = new FormData();
    formData.append('nama', formUser.nama);
    formData.append('username', formUser.username);
    formData.append('role', formUser.role);

    let res;
    if (editingId) {
      formData.append('id', editingId);
      res = await updateUserAction(formData);
    } else {
      formData.append('email', formUser.email);
      formData.append('password', formUser.password);
      res = await createUserAction(formData);
    }

    setSaving(false);
    if (res.success) {
      showToast(res.message, 'success');
      setShowModal(false);
      resetForm();
      loadData();
    } else {
      showToast(res.error, 'error');
    }
  }

  // --- Filter & Pagination ---
  const filteredUsers = useMemo(() => {
    const q = search.toLowerCase();
    return users.filter(u =>
      (u.nama || '').toLowerCase().includes(q) ||
      (u.email || '').toLowerCase().includes(q) ||
      (u.username || '').toLowerCase().includes(q) ||
      (getRoleLabel(u.role) || '').toLowerCase().includes(q)
    );
  }, [users, search]);

  const sortedUsers = useMemo(() => {
    return sortRows(filteredUsers, sort, userSortAccessors);
  }, [filteredUsers, sort]);

  const paginatedUsers = useMemo(() => paginateRows(sortedUsers, page, TABLE_PAGE_SIZE), [sortedUsers, page]);

  function handleSort(key) {
    const nextDir = getNextSort(sort.key, sort.direction, key);
    setSort({ key, direction: nextDir });
  }

  function getBadgeClass(role) {
    if (role === 'owner') return 'badge badge-success';
    if (role === 'super_admin') return 'badge badge-warning';
    if (role === 'admin_keuangan') return 'badge badge-info';
    return 'badge';
  }

  return (
    <AppShell title="Kelola Pengguna" subtitle="Kelola akses akun dan otorisasi pengguna (Khusus Super Admin)">
      {toast && (
        <div className="toast-container">
          <div className={`toast toast-${toast.type}`}>
            <span>{toast.message}</span>
          </div>
        </div>
      )}

      <div className="page-header">
        <div className="toolbar" style={{ flex: 1, marginBottom: 0 }}>
          <div className="search-box" style={{ flex: 1, maxWidth: 420 }}>
            <span className="search-box-icon"><Search size={16} /></span>
            <input
              type="text"
              className="form-input"
              placeholder="Cari nama, username, atau role..."
              value={search}
              onChange={(e) => {
                setSearch(e.target.value);
                setPage(1);
              }}
              style={{ paddingLeft: 40 }}
            />
          </div>
        </div>
        <div style={{ display: 'flex', gap: 10, flexWrap: 'wrap', justifyContent: 'flex-end' }}>
          <button className="btn btn-primary" onClick={() => handleOpenModal()}>+ Tambah Pengguna</button>
        </div>
      </div>

      <div className="card">
        <div className="table-responsive">
          <table className="table">
            <thead>
              <tr>
                <SortableHeader label="Nama Pengguna" sortKey="nama" sort={sort} onSort={handleSort} />
                <SortableHeader label="Email Login" sortKey="email" sort={sort} onSort={handleSort} />
                <SortableHeader label="Username" sortKey="username" sort={sort} onSort={handleSort} />
                <SortableHeader label="Role (Hak Akses)" sortKey="role" sort={sort} onSort={handleSort} />
                <th style={{ textAlign: 'center' }}>Aksi</th>
              </tr>
            </thead>
            <tbody>
              {loading ? (
                <tr>
                  <td colSpan="5">Memuat data pengguna...</td>
                </tr>
              ) : paginatedUsers.rows.length === 0 ? (
                <tr>
                  <td colSpan="5">Tidak ada pengguna ditemukan.</td>
                </tr>
              ) : (
                paginatedUsers.rows.map((u) => (
                  <tr key={u.id}>
                    <td>
                      <div style={{ fontWeight: 600 }}>{u.nama}</div>
                    </td>
                    <td className="table-mono" style={{ color: 'var(--text-secondary)' }}>
                      {u.email}
                    </td>
                    <td className="table-mono" style={{ color: 'var(--text-secondary)' }}>
                      {u.username || '-'}
                    </td>
                    <td>
                      <span className={getBadgeClass(u.role)}>
                        {getRoleLabel(u.role)}
                      </span>
                    </td>
                    <td style={{ textAlign: 'center' }}>
                      <button className="btn btn-ghost btn-sm" onClick={() => handleOpenModal(u)} title="Edit Pengguna">
                        <Pencil size={16} />
                      </button>
                    </td>
                  </tr>
                ))
              )}
            </tbody>
          </table>
          <TablePagination 
            page={paginatedUsers.page}
            totalPages={paginatedUsers.totalPages}
            totalItems={sortedUsers.length}
            startIndex={paginatedUsers.startIndex}
            endIndex={paginatedUsers.endIndex}
            onPageChange={setPage} 
          />
        </div>
      </div>

      {showModal && (
        <div className="modal-overlay" onClick={() => setShowModal(false)}>
          <div className="modal" onClick={(e) => e.stopPropagation()}>
            <div className="modal-header">
              <h3 className="modal-title">{editingId ? 'Edit Pengguna' : 'Tambah Pengguna Baru'}</h3>
              <button className="modal-close" onClick={() => setShowModal(false)} aria-label="Tutup">
                <X size={18} />
              </button>
            </div>
            <form onSubmit={handleSave}>
              <div className="modal-body">
                {!editingId && (
                  <div style={{ padding: 12, backgroundColor: 'rgba(240, 165, 0, 0.1)', color: 'var(--color-warning)', borderRadius: 8, marginBottom: 16, fontSize: 13 }}>
                    <strong>Penting:</strong> Pembuatan akun ini akan mendaftarkan kredensial login secara permanen. {PASSWORD_REQUIREMENTS_MESSAGE}
                  </div>
                )}
                
                <div className="form-group">
                  <label className="form-label form-label-required">Nama Lengkap</label>
                  <input
                    type="text"
                    required
                    className="form-input"
                    value={formUser.nama}
                    onChange={e => setFormUser(prev => ({ ...prev, nama: e.target.value }))}
                    placeholder="Contoh: Budi Santoso"
                  />
                </div>

                {!editingId && (
                  <>
                    <div className="form-group">
                      <label className="form-label form-label-required">Email Login</label>
                      <input
                        type="email"
                        required
                        className="form-input"
                        value={formUser.email}
                        onChange={e => setFormUser(prev => ({ ...prev, email: e.target.value }))}
                        placeholder="Contoh: budi@ramsawit.com"
                      />
                    </div>
                    <div className="form-group">
                      <label className="form-label form-label-required">Password</label>
                      <input
                        type="password"
                        required
                        minLength={PASSWORD_MIN_LENGTH}
                        pattern={PASSWORD_HTML_PATTERN}
                        title="Minimal 12 karakter dengan huruf kecil, huruf besar, angka, dan simbol"
                        autoComplete="new-password"
                        className="form-input"
                        value={formUser.password}
                        onChange={e => setFormUser(prev => ({ ...prev, password: e.target.value }))}
                        placeholder="Minimal 12 karakter + Aa1!"
                      />
                    </div>
                  </>
                )}

                <div className="form-group">
                  <label className="form-label">Username (Opsional)</label>
                  <input
                    type="text"
                    className="form-input"
                    value={formUser.username}
                    onChange={e => setFormUser(prev => ({ ...prev, username: e.target.value }))}
                    placeholder="Contoh: budi123"
                  />
                </div>

                <div className="form-group">
                  <label className="form-label form-label-required">Role (Hak Akses)</label>
                  <select
                    required
                    className="form-input form-select"
                    value={formUser.role}
                    onChange={e => setFormUser(prev => ({ ...prev, role: e.target.value }))}
                  >
                    <option value="admin_operasional">Admin</option>
                    <option value="super_admin">Super Admin</option>
                    <option value="owner">Owner</option>
                  </select>
                </div>
              </div>
              <div className="modal-footer">
                <button type="button" className="btn btn-outline" onClick={() => setShowModal(false)} disabled={saving}>
                  Batal
                </button>
                <button type="submit" className="btn btn-primary" disabled={saving}>
                  {saving ? 'Menyimpan...' : 'Simpan'}
                </button>
              </div>
            </form>
          </div>
        </div>
      )}
    </AppShell>
  );
}
