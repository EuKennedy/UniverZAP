import chatflowsAPI from '../chatflows';

describe('#chatflowsAPI — automação', () => {
  const originalAxios = window.axios;
  const axiosMock = {
    post: vi.fn(() => Promise.resolve()),
    get: vi.fn(() => Promise.resolve()),
  };

  beforeEach(() => {
    window.axios = axiosMock;
    vi.clearAllMocks();
  });

  afterEach(() => {
    window.axios = originalAxios;
  });

  // `options` é uma propriedade do ApiClient: um método com esse nome ficaria
  // escondido e o editor nunca carregaria listas nem outros fluxos.
  it('opções do editor são um método de verdade', () => {
    expect(typeof chatflowsAPI.editorOptions).toBe('function');
    chatflowsAPI.editorOptions();
    expect(axiosMock.get).toHaveBeenCalledWith('/api/v1/chatflows/options');
  });

  it('modelos, funil e simulação', () => {
    chatflowsAPI.templates();
    chatflowsAPI.fromTemplate('beauty_salon/agendamento');
    chatflowsAPI.funnel(3);
    chatflowsAPI.simulate(3, { inputs: ['oi'], seed: 7 });

    expect(axiosMock.get).toHaveBeenCalledWith('/api/v1/chatflows/templates');
    expect(axiosMock.post).toHaveBeenCalledWith(
      '/api/v1/chatflows/from_template',
      { key: 'beauty_salon/agendamento' }
    );
    expect(axiosMock.get).toHaveBeenCalledWith('/api/v1/chatflows/3/funnel', {
      params: { days: 30 },
    });
    expect(axiosMock.post).toHaveBeenCalledWith(
      '/api/v1/chatflows/3/simulate',
      { inputs: ['oi'], seed: 7, contact: undefined }
    );
  });

  it('pausar e retomar o robô na conversa', () => {
    chatflowsAPI.conversationState(42);
    chatflowsAPI.pauseConversation(42);
    chatflowsAPI.resumeConversation(42);

    expect(axiosMock.get).toHaveBeenCalledWith(
      '/api/v1/conversations/42/chatflow_state'
    );
    expect(axiosMock.post).toHaveBeenCalledWith(
      '/api/v1/conversations/42/chatflow_state/pause'
    );
    expect(axiosMock.post).toHaveBeenCalledWith(
      '/api/v1/conversations/42/chatflow_state/resume'
    );
  });
});
