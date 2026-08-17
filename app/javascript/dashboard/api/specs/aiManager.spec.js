import AiManagerAPI from '../aiManager';
import ApiClient from '../ApiClient';

describe('#AiManagerAPI', () => {
  it('creates correct instance', () => {
    expect(AiManagerAPI).toBeInstanceOf(ApiClient);
    expect(AiManagerAPI).toHaveProperty('overview');
    expect(AiManagerAPI).toHaveProperty('listSuggestions');
    expect(AiManagerAPI).toHaveProperty('approveSuggestion');
    expect(AiManagerAPI).toHaveProperty('dismissSuggestion');
    expect(AiManagerAPI).toHaveProperty('estimateRun');
    expect(AiManagerAPI).toHaveProperty('createRun');
    expect(AiManagerAPI).toHaveProperty('listChecks');
    expect(AiManagerAPI).toHaveProperty('updateCheck');
  });

  // A rota exata, e não só "chamou a API". Um approve que caísse em
  // /suggestions/42 sem /approve devolveria 200 no backend errado e a tela
  // tiraria o card da fila achando que aplicou.
  describe('API calls', () => {
    const originalAxios = window.axios;
    const axiosMock = {
      get: vi.fn(() => Promise.resolve()),
      post: vi.fn(() => Promise.resolve()),
      patch: vi.fn(() => Promise.resolve()),
    };

    beforeEach(() => {
      window.axios = axiosMock;
      Object.defineProperty(AiManagerAPI, 'accountIdFromRoute', {
        get: () => '1',
        configurable: true,
      });
    });

    afterEach(() => {
      window.axios = originalAxios;
    });

    it('#overview', () => {
      AiManagerAPI.overview();
      expect(axiosMock.get).toHaveBeenCalledWith(
        '/api/v1/accounts/1/ai/manager/overview'
      );
    });

    it('#listSuggestions defaults to the pending queue', () => {
      AiManagerAPI.listSuggestions();
      expect(axiosMock.get).toHaveBeenCalledWith(
        '/api/v1/accounts/1/ai/manager/suggestions',
        { params: { status: 'pending' } }
      );
    });

    it('#approveSuggestion', () => {
      AiManagerAPI.approveSuggestion(42);
      expect(axiosMock.post).toHaveBeenCalledWith(
        '/api/v1/accounts/1/ai/manager/suggestions/42/approve'
      );
    });

    it('#dismissSuggestion carries the reason', () => {
      AiManagerAPI.dismissSuggestion(42, 'o cliente remarcou por telefone');
      expect(axiosMock.post).toHaveBeenCalledWith(
        '/api/v1/accounts/1/ai/manager/suggestions/42/dismiss',
        { reason: 'o cliente remarcou por telefone' }
      );
    });

    it('#estimateRun', () => {
      AiManagerAPI.estimateRun();
      expect(axiosMock.get).toHaveBeenCalledWith(
        '/api/v1/accounts/1/ai/manager/runs/estimate'
      );
    });

    it('#createRun', () => {
      AiManagerAPI.createRun();
      expect(axiosMock.post).toHaveBeenCalledWith(
        '/api/v1/accounts/1/ai/manager/runs'
      );
    });

    it('#listChecks', () => {
      AiManagerAPI.listChecks();
      expect(axiosMock.get).toHaveBeenCalledWith(
        '/api/v1/accounts/1/ai/manager/checks'
      );
    });

    it('#updateCheck', () => {
      AiManagerAPI.updateCheck('died_on_price', false);
      expect(axiosMock.patch).toHaveBeenCalledWith(
        '/api/v1/accounts/1/ai/manager/checks/died_on_price',
        { enabled: false }
      );
    });
  });
});
