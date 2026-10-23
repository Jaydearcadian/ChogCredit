import { StrictMode } from 'react';
import { createRoot } from 'react-dom/client';
import { BrowserRouter, Route, Routes } from 'react-router-dom';
import Account from './pages/Account';
import { Add, Borrow, Release, Repay, Withdraw } from './pages/Flows';
import Activity from './pages/Activity';
import { Risk } from './pages/Later';
import { SellComplete, SellSetup, SellSign } from './pages/Sell';
import Open from './pages/Open';
import Settings from './pages/Settings';
import { Connect, Pick } from './pages/Start';
import { AppProvider } from './state';
import './styles/tokens.css';
import './styles/base.css';
import './styles/components.css';
import './styles/cream.css';
import './styles/motion.css';

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
          <Route path="/repay" element={<Repay />} />
          <Route path="/withdraw" element={<Withdraw />} />
          <Route path="/release" element={<Release />} />
          <Route path="/activity" element={<Activity />} />
          <Route path="/sell" element={<SellSetup />} />
          <Route path="/sell/sign" element={<SellSign />} />
          <Route path="/sell/complete" element={<SellComplete />} />
          <Route path="/risk" element={<Risk />} />
          <Route path="/settings" element={<Settings />} />
        </Routes>
      </BrowserRouter>
    </AppProvider>
  </StrictMode>,
);
