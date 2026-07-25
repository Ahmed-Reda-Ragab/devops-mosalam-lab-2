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
let currentPage = 1;
let itemsPerPage = 10;

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

async function fetchTasks(page = 1) {
  try {
    clearError();
    currentPage = page;
    const url = new URL(apiUrl, window.location.origin);
    url.searchParams.set('page', page);
    url.searchParams.set('limit', itemsPerPage);
    
    const response = await fetch(url.toString(), { headers: authHeaders() });
    if (!response.ok) {
      throw new Error('Unable to load tasks');
    }
    const payload = await response.json();
    const tasks = Array.isArray(payload) ? payload : payload.tasks || [];
    const pagination = payload.pagination || {};
    
    renderTasks(tasks);
    renderPagination(pagination);
    
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

function renderPagination(pagination) {
  // Remove existing pagination if any
  let paginationDiv = document.getElementById('pagination-controls');
  if (paginationDiv) {
    paginationDiv.remove();
  }
  
  // Only show pagination if there are multiple pages
  if (!pagination || pagination.pages <= 1) {
    return;
  }
  
  paginationDiv = document.createElement('div');
  paginationDiv.id = 'pagination-controls';
  paginationDiv.style.cssText = 'margin-top: 20px; display: flex; gap: 10px; align-items: center; flex-wrap: wrap;';
  
  const info = document.createElement('span');
  info.style.cssText = 'min-width: 200px;';
  info.textContent = `Page ${pagination.page} of ${pagination.pages} (${pagination.total} total)`;
  paginationDiv.appendChild(info);
  
  // Previous button
  const prevBtn = document.createElement('button');
  prevBtn.textContent = '← Previous';
  prevBtn.disabled = pagination.page <= 1;
  prevBtn.addEventListener('click', () => fetchTasks(pagination.page - 1));
  paginationDiv.appendChild(prevBtn);
  
  // Page numbers
  const pagesContainer = document.createElement('div');
  pagesContainer.style.cssText = 'display: flex; gap: 5px; flex-wrap: wrap;';
  
  // Show first page, current page range, and last page
  const startPage = Math.max(1, pagination.page - 2);
  const endPage = Math.min(pagination.pages, pagination.page + 2);
  
  if (startPage > 1) {
    const btn = document.createElement('button');
    btn.textContent = '1';
    btn.addEventListener('click', () => fetchTasks(1));
    pagesContainer.appendChild(btn);
    if (startPage > 2) {
      const dots = document.createElement('span');
      dots.textContent = '...';
      pagesContainer.appendChild(dots);
    }
  }
  
  for (let p = startPage; p <= endPage; p++) {
    const btn = document.createElement('button');
    btn.textContent = p;
    btn.style.cssText = p === pagination.page ? 'font-weight: bold; background-color: #007bff; color: white;' : '';
    btn.disabled = p === pagination.page;
    btn.addEventListener('click', () => fetchTasks(p));
    pagesContainer.appendChild(btn);
  }
  
  if (endPage < pagination.pages) {
    if (endPage < pagination.pages - 1) {
      const dots = document.createElement('span');
      dots.textContent = '...';
      pagesContainer.appendChild(dots);
    }
    const btn = document.createElement('button');
    btn.textContent = pagination.pages;
    btn.addEventListener('click', () => fetchTasks(pagination.pages));
    pagesContainer.appendChild(btn);
  }
  
  paginationDiv.appendChild(pagesContainer);
  
  // Next button
  const nextBtn = document.createElement('button');
  nextBtn.textContent = 'Next →';
  nextBtn.disabled = pagination.page >= pagination.pages;
  nextBtn.addEventListener('click', () => fetchTasks(pagination.page + 1));
  paginationDiv.appendChild(nextBtn);
  
  taskList.parentNode.insertBefore(paginationDiv, taskList.nextSibling);
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
    // Refresh to first page after deletion
    await fetchTasks(1);
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
    // Refresh to first page after creating/updating
    await fetchTasks(1);
  } catch (error) {
    showError(error.message);
  }
}

cancelButton.addEventListener('click', resetForm);
taskForm.addEventListener('submit', submitTask);

fetchTasks();
