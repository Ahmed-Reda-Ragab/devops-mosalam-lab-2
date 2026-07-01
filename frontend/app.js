const backendBaseUrl = new URLSearchParams(window.location.search).get('backend') || `${window.location.hostname}:8000`;
const apiUrl = `http://${backendBaseUrl}/api/tasks`;
const backendUrlLabel = document.getElementById('backend-url');
const taskForm = document.getElementById('task-form');
const taskList = document.getElementById('task-list');
const errorMessage = document.getElementById('error-message');
const cancelButton = document.getElementById('cancel-update');
const formTitle = document.getElementById('form-title');

let editingTaskId = null;

backendUrlLabel.textContent = `http://${backendBaseUrl}`;

function showError(message) {
  errorMessage.textContent = message;
  errorMessage.classList.remove('hidden');
}

function clearError() {
  errorMessage.textContent = '';
  errorMessage.classList.add('hidden');
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
    const response = await fetch(apiUrl);
    if (!response.ok) {
      throw new Error('Unable to load tasks');
    }
    const tasks = await response.json();
    renderTasks(tasks);
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
    const response = await fetch(`${apiUrl}/${taskId}`, { method: 'DELETE' });
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
      headers: { 'Content-Type': 'application/json' },
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
