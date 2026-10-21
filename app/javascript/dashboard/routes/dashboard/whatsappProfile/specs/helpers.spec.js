import {
  apiErrorMessage,
  backgroundClass,
  monthGrid,
  squareCrop,
} from '../helpers';

describe('whatsappProfile helpers', () => {
  // O maior quadrado centralizado é o ponto de partida do recorte.
  it('centres the largest square of a landscape picture', () => {
    expect(squareCrop({ width: 1200, height: 800 })).toEqual({
      size: 800,
      x: 200,
      y: 0,
    });
  });

  it('zooms in and moves within the available slack', () => {
    expect(
      squareCrop({ width: 1000, height: 1000 }, 2, { x: 1, y: -1 })
    ).toEqual({ size: 500, x: 500, y: 0 });
  });

  it('maps a palette colour to its Tailwind class and falls back to the first', () => {
    expect(backgroundClass('#8e44ad')).toBe('bg-[#8E44AD]');
    expect(backgroundClass('#123456')).toBe('bg-[#0A5F55]');
  });

  it('reads the validation message the server sends', () => {
    expect(
      apiErrorMessage({ response: { data: { message: 'Body is blank' } } })
    ).toBe('Body is blank');
  });

  // O calendário sempre tem 6 semanas começando no domingo.
  it('builds a six-week month grid starting on Sunday', () => {
    const grid = monthGrid(new Date(2026, 9, 21));
    expect(grid).toHaveLength(42);
    expect(grid[0].getDay()).toBe(0);
    expect(grid[0] <= new Date(2026, 9, 1)).toBe(true);
    expect(grid.some(day => day.getMonth() === 9 && day.getDate() === 31)).toBe(
      true
    );
  });
});
