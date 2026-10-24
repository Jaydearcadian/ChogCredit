import { StrictMode, Suspense, lazy } from 'react';
import { createRoot } from 'react-dom/client';
import { BrowserRouter, Route, Routes } from 'react-router-dom';
import { Connect, Pick } from './pages/Start';
import { Tour } from './components/demo';
import { Root } from './state';
import './styles/tokens.css';
import './styles/base.css';
import './styles/components.css';
import './styles/cream.css';
import './styles/motion.css';

// Each screen loads when it is first opened, so the landing page does not carry the sell, lend and flow code.
const Account = lazy(() => import('./pages/Account'));
const Flows = () => import('./pages/Flows');
const Add = lazy(() => Flows().then((m) => ({ default: m.Add })));
const Borrow = lazy(() => Flows().then((m) => ({ default: m.Borrow })));
const Release = lazy(() => Flows().then((m) => ({ default: m.Release })));
const Repay = lazy(() => Flows().then((m) => ({ default: m.Repay })));
const Withdraw = lazy(() => Flows().then((m) => ({ default: m.Withdraw })));
const Activity = lazy(() => import('./pages/Activity'));
const Explore = lazy(() => import('./pages/Explore'));
const Lend = lazy(() => import('./pages/Lend'));
const Risk = lazy(() => import('./pages/Later').then((m) => ({ default: m.Risk })));
const SellPages = () => import('./pages/Sell');
const SellSetup = lazy(() => SellPages().then((m) => ({ default: m.SellSetup })));
const SellSign = lazy(() => SellPages().then((m) => ({ default: m.SellSign })));
const SellComplete = lazy(() => SellPages().then((m) => ({ default: m.SellComplete })));
const Open = lazy(() => import('./pages/Open'));
const Receive = lazy(() => import('./pages/Receive'));
const Pay = lazy(() => import('./pages/Receive').then((m) => ({ default: m.Pay })));
const Settings = lazy(() => import('./pages/Settings'));

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <Root>
      <BrowserRouter>
        <Suspense fallback={null}>
        <Routes>
          <Route path="/" element={<Connect />} />
          <Route path="/pick" element={<Pick />} />
          <Route path="/explore" element={<Explore />} />
          <Route path="/lend" element={<Lend />} />
          <Route path="/receive" element={<Receive />} />
          <Route path="/pay/:id" element={<Pay />} />
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
        </Suspense>
        <Tour />
      </BrowserRouter>
    </Root>
  </StrictMode>,
);
