import axios from 'axios';
import TasksAPI from '../tasks';
import ApiClient from '../ApiClient';

global.axios = axios;
vi.mock('axios');

describe('#TasksAPI', () => {
  it('creates correct instance', () => {
    expect(TasksAPI).toBeInstanceOf(ApiClient);
    expect(TasksAPI).toHaveProperty('get');
    expect(TasksAPI).toHaveProperty('show');
    expect(TasksAPI).toHaveProperty('create');
    expect(TasksAPI).toHaveProperty('update');
    expect(TasksAPI).toHaveProperty('delete');
    expect(TasksAPI).toHaveProperty('fetch');
    expect(TasksAPI).toHaveProperty('assign');
    expect(TasksAPI).toHaveProperty('unassign');
    expect(TasksAPI).toHaveProperty('complete');
    expect(TasksAPI).toHaveProperty('addComment');
    expect(TasksAPI).toHaveProperty('fetchActivities');
  });

  it('passes filter params to the index endpoint', () => {
    axios.get.mockResolvedValue({ data: [] });
    const params = { scope: 'mine', status: 'open', urgency: 'urgent' };
    TasksAPI.fetch(params);
    expect(axios.get).toHaveBeenCalledWith(expect.stringContaining('/tasks'), {
      params,
    });
  });

  it('wraps create body under `task`', () => {
    axios.post.mockResolvedValue({ data: { id: 1 } });
    const payload = { title: 'New task', urgency: 'high' };
    TasksAPI.create(payload);
    expect(axios.post).toHaveBeenCalledWith(expect.stringContaining('/tasks'), {
      task: payload,
    });
  });

  it('hits the assign member route with user_id', () => {
    axios.post.mockResolvedValue({ data: {} });
    TasksAPI.assign(42, 9);
    expect(axios.post).toHaveBeenCalledWith(
      expect.stringContaining('/tasks/42/assign'),
      { user_id: 9 }
    );
  });

  it('deletes assignment by user_id', () => {
    axios.delete.mockResolvedValue({ data: {} });
    TasksAPI.unassign(42, 9);
    expect(axios.delete).toHaveBeenCalledWith(
      expect.stringContaining('/tasks/42/assignees/9')
    );
  });

  it('completes by posting to the complete member route', () => {
    axios.post.mockResolvedValue({ data: {} });
    TasksAPI.complete(42);
    expect(axios.post).toHaveBeenCalledWith(
      expect.stringContaining('/tasks/42/complete')
    );
  });

  it('posts a comment body to the comments route', () => {
    axios.post.mockResolvedValue({ data: {} });
    TasksAPI.addComment(42, { text: 'hi' });
    expect(axios.post).toHaveBeenCalledWith(
      expect.stringContaining('/tasks/42/comments'),
      { body: { text: 'hi' } }
    );
  });

  it('passes page params to activities endpoint', () => {
    axios.get.mockResolvedValue({ data: { data: [] } });
    TasksAPI.fetchActivities(42, { page: 2 });
    expect(axios.get).toHaveBeenCalledWith(
      expect.stringContaining('/tasks/42/activities'),
      { params: { page: 2 } }
    );
  });
});
