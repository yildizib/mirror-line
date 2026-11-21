import AxeBuilder from '@axe-core/playwright';
import { expect, test } from '@playwright/test';
import { screens } from '../src/screens';

test.describe.configure({ mode: 'serial' });

test('registry renders every screen ID and required state', async ({ page }) => {
  test.setTimeout(180_000);
  for (const screen of screens) {
    for (const variant of screen.variants) {
      await page.goto(`/#/screen/${screen.id}?variant=${encodeURIComponent(variant)}&locale=tr&capture=1`);
      const viewport = page.locator('[data-screen-id]');
      await expect(viewport).toHaveAttribute('data-screen-id', screen.id);
      await expect(viewport).toHaveAttribute('data-variant', variant);
      await expect(page.locator('.mobile-screen')).toBeVisible();
    }
  }
});

test('canonical viewport has no horizontal overflow and meets base sizing rules', async ({ page }) => {
  const representative = ['A03', 'R06', 'P05', 'SP01', 'M01', 'S01', 'MS01', 'SS01', 'X06'];
  for (const id of representative) {
    const definition = screens.find((screen) => screen.id === id)!;
    await page.goto(`/#/screen/${id}?variant=${encodeURIComponent(definition.variants[0])}&locale=tr&capture=1`);
    const metrics = await page.evaluate(() => {
      const root = document.documentElement;
      const textSizes = [...document.querySelectorAll('body *')]
        .filter((element) => (element.textContent || '').trim().length > 0)
        .map((element) => Number.parseFloat(getComputedStyle(element).fontSize));
      const controls = [...document.querySelectorAll<HTMLElement>('button, a, input, select')]
        .filter((element) => element.getClientRects().length > 0)
        .map((element) => ({ width: element.getBoundingClientRect().width, height: element.getBoundingClientRect().height }));
      return {
        overflow: root.scrollWidth - root.clientWidth,
        minText: Math.min(...textSizes),
        undersizedControls: controls.filter((control) => control.width < 48 || control.height < 48),
      };
    });
    expect(metrics.overflow, `${id} horizontal overflow`).toBeLessThanOrEqual(1);
    expect(metrics.minText, `${id} minimum text size`).toBeGreaterThanOrEqual(14);
    expect(metrics.undersizedControls, `${id} touch targets`).toEqual([]);
  }
});

test('core screens have no serious accessibility violations', async ({ page }) => {
  const representative = ['A03', 'R01', 'P06', 'SP03', 'M01', 'S04', 'MS01', 'X06'];
  for (const id of representative) {
    const definition = screens.find((screen) => screen.id === id)!;
    await page.goto(`/#/screen/${id}?variant=${encodeURIComponent(definition.variants[0])}&locale=tr&capture=1`);
    const results = await new AxeBuilder({ page }).analyze();
    const serious = results.violations.filter((violation) => ['critical', 'serious'].includes(violation.impact || ''));
    expect(serious, `${id} accessibility violations`).toEqual([]);
  }
});

test('English expansion and 200 percent text size remain usable', async ({ page }) => {
  for (const width of [360, 412, 480]) {
    await page.setViewportSize({ width, height: 915 });
    await page.goto('/#/screen/SS01?variant=default&locale=en&capture=1');
    await page.addStyleTag({ content: 'html { font-size: 200% !important; }' });
    const overflow = await page.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth);
    expect(overflow).toBeLessThanOrEqual(1);
    await expect(page.getByRole('navigation')).toBeVisible();
  }
});

test('update can be deferred without blocking the current destination', async ({ page }) => {
  await page.goto('/#/screen/A10?variant=visible&locale=tr&capture=1');
  await page.getByRole('button', { name: 'Daha sonra' }).click();
  await expect(page.locator('[data-variant="dismissed"]')).toBeVisible();
  await expect(page.locator('.state-notice')).toContainText('tekrar önerilmeyecek');
});

test('role-specific permission boundaries stay separate', async ({ page }) => {
  await page.goto('/#/screen/MP01?variant=default&locale=tr&capture=1');
  await expect(page.getByText('Ana Telefon yalnızca bildirim izni ister.')).toBeVisible();
  await expect(page.getByText('SMS erişimi')).toHaveCount(0);
  await page.goto('/#/screen/SP01?variant=fresh&locale=tr&capture=1');
  await expect(page.getByText('Arama izleme')).toBeVisible();
  await expect(page.getByText('SMS')).toBeVisible();
});
