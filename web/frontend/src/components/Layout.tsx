import { useEffect, useState, type KeyboardEvent, type ReactNode } from 'react';
import { verificationApi } from '../api/api';
import { useAuth } from '../state/AuthContext';
import { IconGrid, IconLogout, IconSearch, IconShield, IconStore, IconUsers, IconCamera, IconBox, IconBag, IconSettings } from './icons';

export type PageKey = 'overview' | 'users' | 'suppliers' | 'verification' | 'product-flags' | 'products' | 'orders' | 'audit' | 'settings';

export const PAGE_META: Record<PageKey, { title: string; breadcrumb: string }> = {
  overview: { title: 'Overview', breadcrumb: 'Health' },
  users: { title: 'Users', breadcrumb: 'All users' },
  suppliers: { title: 'Suppliers', breadcrumb: 'Sellers' },
  verification: { title: 'Verification', breadcrumb: 'IC queue' },
  'product-flags': { title: 'Photo flags', breadcrumb: 'Photo flags' },
  products: { title: 'Products', breadcrumb: 'Catalog' },
  orders: { title: 'Orders', breadcrumb: 'Catalog' },
  audit: { title: 'Audit log', breadcrumb: 'System' },
  settings: { title: 'Settings', breadcrumb: 'System' },
};

interface Props {
  current: PageKey;
  onNavigate: (page: PageKey) => void;
  /** Global search value — filters the users table on the directory pages. */
  query: string;
  onQueryChange: (value: string) => void;
  children: ReactNode;
}

interface NavItem {
  key: PageKey;
  label: string;
  icon: ReactNode;
}

const NAV_GROUPS: { label: string; items: NavItem[] }[] = [
  {
    label: 'Monitor',
    items: [
      {
        key: 'overview',
        label: 'Overview',
        icon: <IconGrid size={17} />,
      },
      {
        key: 'product-flags',
        label: 'Photo flags',
        icon: <IconCamera size={17} />,
      },
    ],
  },
  {
    label: 'Directory',
    items: [
      {
        key: 'users',
        label: 'Users',
        icon: <IconUsers size={17} />,
      },
      {
        key: 'suppliers',
        label: 'Suppliers',
        icon: <IconStore size={17} />,
      },
      {
        key: 'verification',
        label: 'Verification',
        icon: <IconShield size={17} />,
      },
    ],
  },
  {
    label: 'Catalog',
    items: [
      {
        key: 'products',
        label: 'Products',
        icon: <IconBox size={17} />,
      },
      {
        key: 'orders',
        label: 'Orders',
        icon: <IconBag size={17} />,
      },
    ],
  },
  {
    label: 'System',
    items: [
      {
        key: 'audit',
        label: 'Audit log',
        icon: <IconShield size={17} />,
      },
      {
        key: 'settings',
        label: 'Settings',
        icon: <IconSettings size={17} />,
      },
    ],
  },
];

/**
 * App shell: dark brand sidebar (grouped nav, active state, admin identity +
 * sign-out at the bottom) and a sticky topbar carrying the breadcrumb, page
 * title and a global search that drives the users table. Under 900px the
 * sidebar collapses to an icon rail; on phones (under 640px) it becomes a
 * slide-in panel opened from the topbar menu button.
 */
export function Layout({ current, onNavigate, query, onQueryChange, children }: Props) {
  const { user, logout } = useAuth();
  const meta = PAGE_META[current];

  // Phones: the sidebar is a slide-in panel opened from the topbar menu
  // button; it closes on navigation, on the backdrop, or with Escape.
  const [menuOpen, setMenuOpen] = useState(false);
  const go = (page: PageKey) => {
    setMenuOpen(false);
    onNavigate(page);
  };
  useEffect(() => {
    if (!menuOpen) return;
    const onKey = (e: globalThis.KeyboardEvent) => {
      if (e.key === 'Escape') setMenuOpen(false);
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [menuOpen]);

  // Pending-verification count for the sidebar badge. Best-effort: failures
  // are silent here (the Verification page surfaces its own error state) —
  // a 401 still triggers the shared logout event from the API client.
  const [pendingReviews, setPendingReviews] = useState(0);
  useEffect(() => {
    let cancelled = false;
    verificationApi
      .list('pending', { limit: 1 })
      .then((res) => {
        if (!cancelled) setPendingReviews(res.total);
      })
      .catch(() => undefined);
    return () => {
      cancelled = true;
    };
  }, [current]);

  const onSearchKeyDown = (e: KeyboardEvent<HTMLInputElement>) => {
    if (e.key !== 'Enter') return;
    e.preventDefault();
    // On the overview page the search jumps into the directory with the
    // query applied; on directory pages it already filters the table.
    if (current === 'overview') go('users');
  };

  return (
    <div className={`shell ${menuOpen ? 'menu-open' : ''}`}>
      <div
        className="sidebar-backdrop"
        aria-hidden="true"
        onClick={() => setMenuOpen(false)}
      />
      <aside className={`sidebar ${menuOpen ? 'open' : ''}`} id="admin-sidebar">
        <div className="brand">
          <span className="brand-mark" aria-hidden="true">
            I
          </span>
          <span className="brand-text">
            Intellar
            <small>Admin console</small>
          </span>
        </div>

        <nav className="nav" aria-label="Primary">
          {NAV_GROUPS.map((group) => (
            <div className="nav-group" key={group.label}>
              <div className="nav-group-label">{group.label}</div>
              {group.items.map((item) => (
                <button
                  key={item.key}
                  className={`nav-item ${current === item.key ? 'active' : ''}`}
                  onClick={() => go(item.key)}
                  aria-current={current === item.key ? 'page' : undefined}
                  title={item.label}
                >
                  {item.icon}
                  <span>{item.label}</span>
                  {item.key === 'verification' && pendingReviews > 0 && (
                    <span className="nav-count" aria-label={`${pendingReviews} awaiting review`}>
                      {pendingReviews > 99 ? '99+' : pendingReviews}
                    </span>
                  )}
                </button>
              ))}
            </div>
          ))}
        </nav>

        <div className="sidebar-spacer" />

        <div className="sidebar-footer">
          <div className="whoami" title={user?.email ?? undefined}>
            <span className="avatar" aria-hidden="true">
              {(user?.email ?? '?').charAt(0).toUpperCase()}
            </span>
            <span className="whoami-meta">
              <span className="whoami-name">Signed in</span>
              <span className="whoami-email">{user?.email}</span>
            </span>
          </div>
          <button className="nav-item signout" onClick={logout} title="Sign out">
            <IconLogout size={17} />
            <span>Sign out</span>
          </button>
        </div>
      </aside>

      <div className="main">
        <header className="topbar">
          <button
            type="button"
            className="menu-toggle"
            aria-label={menuOpen ? 'Close menu' : 'Open menu'}
            aria-expanded={menuOpen}
            aria-controls="admin-sidebar"
            onClick={() => setMenuOpen((open) => !open)}
          >
            <span className="menu-toggle-bars" aria-hidden="true" />
          </button>
          <div className="topbar-left">
            <div className="breadcrumb" aria-hidden="true">
              <span>Admin</span>
              <span className="breadcrumb-sep">/</span>
              <span>{meta.breadcrumb}</span>
            </div>
            <h1 className="topbar-title">{meta.title}</h1>
          </div>
          <div className="topbar-right">
            <label className="search-global">
              <IconSearch size={15} />
              <input
                type="search"
                placeholder="Search name, email, business…"
                aria-label="Search users"
                value={query}
                onChange={(e) => onQueryChange(e.target.value)}
                onKeyDown={onSearchKeyDown}
              />
            </label>
          </div>
        </header>

        <main className="content">{children}</main>
      </div>
    </div>
  );
}
