// API is served same-origin via the nginx reverse proxy (/api -> backend).
// Optional ?backend=<baseUrl> overrides it for testing against a direct backend.
const apiBase = new URLSearchParams(window.location.search).get('backend') || '';
const apiUrl = `${apiBase}/api/tasks`;

// API key sent as X-API-KEY on every /api call. It's editable in the UI
// (#api-key input, pre-filled with a default) so you can change it while
// testing; the last value is remembered in localStorage across reloads.
// NOTE: this value ships to the browser, so it is visible to anyone using the app.
const apiKeyInput = document.getElementById('api-key');

// A previously-saved key (from testing) overrides the default in the HTML.
const savedApiKey = localStorage.getItem('apiKey');
if (savedApiKey !== null) {
  apiKeyInput.value = savedApiKey;
}
apiKeyInput.addEventListener('change', () => {
  localStorage.setItem('apiKey', apiKeyInput.value.trim());
});

// Merge the current API-key header with any per-request headers (e.g. Content-Type).
function authHeaders(extra) {
  const headers = extra ? { ...extra } : {};
  const key = apiKeyInput.value.trim();
  if (key) {
    headers['X-API-KEY'] = key;
  }
  return headers;
}
const backendUrlLabel = document.getElementById('backend-url');
const taskForm = document.getElementById('task-form');
const taskList = document.getElementById('task-list');
const errorMessage = document.getElementById('error-message');
const cancelButton = document.getElementById('cancel-update');
const formTitle = document.getElementById('form-title');
const cacheStatus = document.getElementById('cache-status');
const containerIdLabel = document.getElementById('container-id');

let editingTaskId = null;

backendUrlLabel.textContent = apiBase || `${window.location.origin}/api`;

function showError(message) {
  errorMessage.textContent = message;
  errorMessage.classList.remove('hidden');
}

function clearError() {
  errorMessage.textContent = '';
  errorMessage.classList.add('hidden');
}

function showCacheStatus(message) {
  if (!cacheStatus) {
    return;
  }
  cacheStatus.textContent = message;
  cacheStatus.classList.remove('hidden');
}

function clearCacheStatus() {
  if (!cacheStatus) {
    return;
  }
  cacheStatus.textContent = '';
  cacheStatus.classList.add('hidden');
}

function resetForm() {
  taskForm.reset();
  editingTaskId = null;
  formTitle.textContent = 'Create Task';
  cancelButton.classList.add('hidden');
}

async function fetchTasks() {
  try {
    clearError();
    const response = await fetch(apiUrl, { headers: authHeaders() });
    if (!response.ok) {
      throw new Error('Unable to load tasks');
    }
    const payload = await response.json();
    const tasks = Array.isArray(payload) ? payload : payload.tasks || [];
    renderTasks(tasks);
    if (payload.source && payload.message) {
      showCacheStatus(payload.message);
    } else {
      clearCacheStatus();
    }
    if (payload.container) {
      document.getElementById('container-id-value').textContent = payload.container;
    }

  } catch (error) {
    showError(error.message);
  }
}

function renderTasks(tasks) {
  taskList.innerHTML = '';
  if (!tasks.length) {
    taskList.innerHTML = '<li>No tasks available.</li>';
    return;
  }

  tasks.forEach((task) => {
    const item = document.createElement('li');
    item.className = 'task-item';
    item.innerHTML = `
      <h3>${task.name}</h3>
      <div class="task-meta">
        <span>Status: ${task.status}</span>
        <span>Updated: ${new Date(task.updated_at).toLocaleString()}</span>
      </div>
      <p>${task.description || ''}</p>
      <div class="task-actions">
        <button type="button" class="edit-button">Edit</button>
        <button type="button" class="delete-button">Delete</button>
      </div>
    `;

    item.querySelector('.edit-button').addEventListener('click', () => startEdit(task));
    item.querySelector('.delete-button').addEventListener('click', () => deleteTask(task.id));

    taskList.appendChild(item);
  });
}

function startEdit(task) {
  editingTaskId = task.id;
  document.getElementById('task-name').value = task.name;
  document.getElementById('task-description').value = task.description || '';
  document.getElementById('task-status').value = task.status;
  formTitle.textContent = 'Update Task';
  cancelButton.classList.remove('hidden');
}

async function deleteTask(taskId) {
  if (!confirm('Delete this task?')) {
    return;
  }

  try {
    clearError();
    const response = await fetch(`${apiUrl}/${taskId}`, { method: 'DELETE', headers: authHeaders() });
    if (!response.ok) {
      throw new Error('Unable to delete task');
    }
    await fetchTasks();
  } catch (error) {
    showError(error.message);
  }
}

async function submitTask(event) {
  event.preventDefault();
  const payload = {
    name: document.getElementById('task-name').value.trim(),
    description: document.getElementById('task-description').value.trim(),
    status: document.getElementById('task-status').value,
  };

  const method = editingTaskId ? 'PUT' : 'POST';
  const url = editingTaskId ? `${apiUrl}/${editingTaskId}` : apiUrl;

  try {
    clearError();
    const response = await fetch(url, {
      method,
      headers: authHeaders({ 'Content-Type': 'application/json' }),
      body: JSON.stringify(payload),
    });

    if (!response.ok) {
      const errorData = await response.json().catch(() => ({}));
      throw new Error(errorData.detail || 'Unable to save task');
    }

    resetForm();
    await fetchTasks();
  } catch (error) {
    showError(error.message);
  }
}

cancelButton.addEventListener('click', resetForm);
taskForm.addEventListener('submit', submitTask);

fetchTasks();
