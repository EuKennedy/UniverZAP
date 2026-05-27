import { useCaptain } from '../useCaptain';
import {
  useFunctionGetter,
  useMapGetter,
  useStore,
} from 'dashboard/composables/store';
import { useAccount } from 'dashboard/composables/useAccount';
import { useConfig } from 'dashboard/composables/useConfig';
import { useAthenasAssistant } from 'dashboard/composables/useAthenasAssistant';
import { useI18n } from 'vue-i18n';
import TasksAPI from 'dashboard/api/captain/tasks';
import AthenasAssistantsAPI from 'dashboard/api/athenas';

vi.mock('dashboard/composables/store');
vi.mock('dashboard/composables/useAccount');
vi.mock('dashboard/composables/useConfig');
vi.mock('dashboard/composables/useAthenasAssistant');
vi.mock('vue-i18n');
vi.mock('dashboard/api/captain/tasks');
vi.mock('dashboard/api/athenas');
vi.mock('dashboard/helper/AnalyticsHelper/index', async importOriginal => {
  const actual = await importOriginal();
  actual.default = {
    track: vi.fn(),
  };
  return actual;
});
vi.mock('dashboard/helper/AnalyticsHelper/events', () => ({
  CAPTAIN_EVENTS: {
    TEST_EVENT: 'captain_test_event',
  },
}));

describe('useCaptain', () => {
  const mockStore = {
    dispatch: vi.fn(),
  };

  beforeEach(() => {
    vi.clearAllMocks();
    useStore.mockReturnValue(mockStore);
    useFunctionGetter.mockReturnValue({ value: 'Draft message' });
    useMapGetter.mockImplementation(getter => {
      const mockValues = {
        'accounts/getUIFlags': { isFetchingLimits: false },
        getSelectedChat: { id: '123' },
        'draftMessages/getReplyEditorMode': 'reply',
      };
      return { value: mockValues[getter] };
    });
    useI18n.mockReturnValue({ t: vi.fn() });
    useAccount.mockReturnValue({
      isCloudFeatureEnabled: vi.fn().mockReturnValue(true),
      currentAccount: { value: { limits: { captain: {} } } },
    });
    useConfig.mockReturnValue({
      isEnterprise: false,
    });
    // Athenas assistant picker — the composable returns a reactive ref-like
    // shape, so we mock activeAssistantId as a value-bearing object that the
    // implementation reads via `.value`.
    useAthenasAssistant.mockReturnValue({
      activeAssistantId: { value: null },
    });
  });

  it('initializes computed properties correctly', async () => {
    const { captainEnabled, captainTasksEnabled, currentChat, draftMessage } =
      useCaptain();

    expect(captainEnabled.value).toBe(true);
    expect(captainTasksEnabled.value).toBe(true);
    expect(currentChat.value).toEqual({ id: '123' });
    expect(draftMessage.value).toBe('Draft message');
  });

  it('rewrites content via Athenas', async () => {
    AthenasAssistantsAPI.rewrite.mockResolvedValue({
      data: { message: 'Rewritten content' },
    });

    const { rewriteContent } = useCaptain();
    const result = await rewriteContent('Original content', 'improve', {});

    expect(AthenasAssistantsAPI.rewrite).toHaveBeenCalledWith(
      {
        content: 'Original content',
        operation: 'improve',
        conversationId: '123',
        assistantId: null,
      },
      { signal: undefined }
    );
    // followUpContext is always null for Athenas-backed rewrites — the
    // assistant is stateless on this endpoint, so the UI's follow-up
    // chain only stays active for the legacy Captain `followUp` method.
    expect(result).toEqual({
      message: 'Rewritten content',
      followUpContext: null,
    });
  });

  it('summarizes conversation via Athenas', async () => {
    AthenasAssistantsAPI.summarize.mockResolvedValue({
      data: { summary: 'Summary' },
    });

    const { summarizeConversation } = useCaptain();
    const result = await summarizeConversation({});

    expect(AthenasAssistantsAPI.summarize).toHaveBeenCalledWith('123', {
      signal: undefined,
      assistantId: null,
    });
    expect(result).toEqual({
      message: 'Summary',
      followUpContext: null,
    });
  });

  it('gets reply suggestion via Athenas', async () => {
    AthenasAssistantsAPI.suggest.mockResolvedValue({
      data: { suggestion: 'Reply suggestion' },
    });

    const { getReplySuggestion } = useCaptain();
    const result = await getReplySuggestion({});

    expect(AthenasAssistantsAPI.suggest).toHaveBeenCalledWith('123', {
      signal: undefined,
      assistantId: null,
    });
    expect(result).toEqual({
      message: 'Reply suggestion',
      followUpContext: null,
    });
  });

  it('sends follow-up message', async () => {
    // Follow-up still uses TasksAPI (Captain legacy path) because the
    // Athenas API does not expose a follow-up endpoint yet — the legacy
    // chain is the only one carrying `followUpContext`.
    TasksAPI.followUp.mockResolvedValue({
      data: {
        message: 'Follow-up response',
        follow_up_context: { id: 'ctx4' },
      },
    });

    const { followUp } = useCaptain();
    const result = await followUp({
      followUpContext: { id: 'ctx3' },
      message: 'Make it shorter',
    });

    expect(TasksAPI.followUp).toHaveBeenCalledWith(
      {
        followUpContext: { id: 'ctx3' },
        message: 'Make it shorter',
        conversationId: '123',
      },
      undefined
    );
    expect(result).toEqual({
      message: 'Follow-up response',
      followUpContext: { id: 'ctx4' },
    });
  });

  it('processes event and routes to correct method', async () => {
    AthenasAssistantsAPI.summarize.mockResolvedValue({
      data: { summary: 'Summary' },
    });
    AthenasAssistantsAPI.suggest.mockResolvedValue({
      data: { suggestion: 'Reply' },
    });
    AthenasAssistantsAPI.rewrite.mockResolvedValue({
      data: { message: 'Rewritten' },
    });

    const { processEvent } = useCaptain();

    await processEvent('summarize', '', {});
    expect(AthenasAssistantsAPI.summarize).toHaveBeenCalled();

    await processEvent('reply_suggestion', '', {});
    expect(AthenasAssistantsAPI.suggest).toHaveBeenCalled();

    await processEvent('improve', 'content', {});
    expect(AthenasAssistantsAPI.rewrite).toHaveBeenCalled();
  });
});
