import './globals.css';

export const metadata = {
  title: 'Sawit CB — Sistem Pencatatan RAM Kelapa Sawit',
  description:
    'Aplikasi manajemen operasional RAM kelapa sawit. Pencatatan pembelian TBS, hutang petani, pengiriman pabrik, biaya operasional, dan laporan keuangan.',
};

export const viewport = {
  width: 'device-width',
  initialScale: 1,
  maximumScale: 1,
};

export default function RootLayout({ children }) {
  return (
    <html lang="id">
      <head>
        <meta name="theme-color" content="#0B1120" />
        <link rel="icon" href="/favicon.ico" />
      </head>
      <body>{children}</body>
    </html>
  );
}
