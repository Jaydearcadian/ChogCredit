import { StrictMode } from 'react';
import { createRoot } from 'react-dom/client';
import { BrowserRouter, Route, Routes } from 'react-router-dom';
import Account from './pages/Account';
import Add from './pages/Add';
import { Borrow, Release, Withdraw } from './pages/Credit';
import { Activity, Risk, Sell } from './pages/Later';
import Open from './pages/Open';
import { Connect, Pick } from './pages/Start';
import { AppProvider } from './state';
import './styles/tokens.css';
import './styles/global.css';

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <AppProvider>
      <BrowserRouter>
        <Routes>
          <Route path="/" element={<Connect />} />
          <Route path="/pick" element={<Pick />} />
          <Route path="/open/:id" element={<Open />} />
          <Route path="/account" element={<Account />} />
          <Route path="/add" element={<Add />} />
          <Route path="/borrow" element={<Borrow />} />
          <Route path="/withdraw" element={<Withdraw />} />
          <Route path="/release" element={<Release />} />
          <Route path="/activity" element={<Activity />} />
          <Route path="/sell" element={<Sell />} />
          <Route path="/risk" element={<Risk />} />
        </Routes>
      </BrowserRouter>
    </AppProvider>
  </StrictMode>,
);
