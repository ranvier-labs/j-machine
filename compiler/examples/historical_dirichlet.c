/*
 * Attributed executable realization based on Figures 5.3-5.5 in Daniel Maskit,
 * "A Message-Driven Programming System for Fine-Grain Multicomputers," Caltech
 * master's thesis, 1994, DOI 10.7907/Z9J38QKJ. See
 * historical/PROVENANCE.md for the complete source and adaptation record.
 *
 * The thesis gives the parallel algorithm and handler pseudocode, not its full
 * application source. This integer four-node ring preserves the described
 * phases: distributed initialization, an initial barrier, neighbor face
 * exchange, receipt counting, a norm barrier after every timestep, and
 * termination or restart. Fixed-point integer smoothing replaces the
 * unavailable original numerical library and file-based graph input.
 */

#define FACE_WORDS 4
#define RECVPORTS 2
#define MAX_STEPS 8
#define EPSILON_DENOMINATOR 64

int local_value = 0;
int pending = 0;
int local_steps = 0;
int node_done_flag = 0;
int receive_sum = 0;
int term_cond = 0;

/* These coordinator fields are observed only on logical rank zero. */
int initial_count = 0;
int setup_count = 0;
int ready_count = 0;
int barrier_count = 0;
int norm_sum = 0;
int global_norm = 0;
int global_step = 0;
int done_count = 0;
int final_checksum = 0;
int step_checksum = 0;

void timestep_send(void);

void node_done(int rank, int value, int steps) {
  done_count++;
  final_checksum = final_checksum + value;
  step_checksum = step_checksum + steps;
}

void timestep_ready(void) {
  int rank = 0;
  ready_count++;
  if (ready_count == computers()) {
    ready_count = 0;
    for (rank = 0; rank < computers(); rank++) {
      timestep_send()@rank;
    }
  }
}

void terminate(int next_global_norm, int step) {
  global_norm = next_global_norm;
  if (next_global_norm > term_cond && step < MAX_STEPS) {
    pending = RECVPORTS;
    receive_sum = 0;
    timestep_ready()@0;
  } else {
    node_done_flag = 1;
    node_done(computer(), local_value, local_steps)@0;
  }
}

void barrier_report(int rank, int local_norm) {
  int destination = 0;
  barrier_count++;
  norm_sum = norm_sum + local_norm;
  if (barrier_count == computers()) {
    global_norm = norm_sum;
    global_step++;
    barrier_count = 0;
    norm_sum = 0;
    for (destination = 0; destination < computers(); destination++) {
      terminate(global_norm, global_step)@destination;
    }
  }
}

void timestep_recv(int source, int len, int *face) {
  int i = 0;
  int old_value = 0;
  int neighbor_average = 0;
  int local_norm = 0;

  for (i = 0; i < len; i++) {
    receive_sum = receive_sum + face[i];
  }
  pending--;
  if (pending == 0) {
    old_value = local_value;
    neighbor_average = receive_sum / (len * RECVPORTS);
    local_value = (old_value + neighbor_average) / 2;
    if (local_value < old_value) local_norm = old_value - local_value;
    else local_norm = local_value - old_value;
    local_steps++;
    barrier_report(computer(), local_norm)@0;
  }
}

void timestep_send(void) {
  int i = 0;
  int left = (computer() + computers() - 1) % computers();
  int right = (computer() + 1) % computers();
  int face[FACE_WORDS];
  for (i = 0; i < FACE_WORDS; i++) face[i] = local_value;
  timestep_recv(computer(), sizeof(face), face)@left;
  timestep_recv(computer(), sizeof(face), face)@right;
}

void setup_ready(void) {
  int rank = 0;
  setup_count++;
  if (setup_count == computers()) {
    for (rank = 0; rank < computers(); rank++) {
      timestep_send()@rank;
    }
  }
}

void initial_setup(int initial_global_norm) {
  term_cond = initial_global_norm / EPSILON_DENOMINATOR;
  pending = RECVPORTS;
  receive_sum = 0;
  setup_ready()@0;
}

void initial_report(int rank, int local_norm) {
  int destination = 0;
  initial_count++;
  norm_sum = norm_sum + local_norm;
  if (initial_count == computers()) {
    global_norm = norm_sum;
    norm_sum = 0;
    for (destination = 0; destination < computers(); destination++) {
      initial_setup(global_norm)@destination;
    }
  }
}

void startnode(void) {
  local_value = computer() * 4;
  initial_report(computer(), local_value)@0;
}

int main(void) {
  int rank = 0;
  for (rank = 0; rank < computers(); rank++) {
    startnode()@rank;
  }
  return 0;
}
