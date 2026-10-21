import {
  COVER_THEMES,
  autoCoverTheme,
  coverClassFor,
  coverThemeFor,
  workspaceInitials,
} from '../workspaceCover';

describe('workspaceCover', () => {
  it('uses the chosen theme when it is a known one', () => {
    expect(coverThemeFor({ name: 'biomelan', cover_theme: 'sunset' })).toBe(
      'sunset'
    );
    expect(coverClassFor({ name: 'biomelan', cover_theme: 'solid_iris' })).toBe(
      'bg-n-iris-9'
    );
  });

  it('falls back to a stable gradient derived from the name', () => {
    const theme = coverThemeFor({ name: 'nutriformulas', cover_theme: null });

    expect(theme).toBe(autoCoverTheme('nutriformulas'));
    expect(theme).toBe(coverThemeFor({ name: 'NUTRIFORMULAS' }));
    expect(COVER_THEMES[theme]).toContain('bg-');
    expect(theme.startsWith('solid_')).toBe(false);
    expect(theme).not.toBe('graphite');
  });

  it('ignores a theme the front end does not know', () => {
    expect(coverThemeFor({ name: 'lizzon', cover_theme: 'neon' })).toBe(
      autoCoverTheme('lizzon')
    );
  });

  it('builds initials from the first two words, skipping punctuation', () => {
    expect(workspaceInitials('BEAUTY CENTER BH LOURDES - Estética')).toBe('BC');
    expect(workspaceInitials('biomelan')).toBe('BI');
    expect(workspaceInitials('Ótica - Visão')).toBe('ÓV');
    expect(workspaceInitials('')).toBe('?');
  });
});
