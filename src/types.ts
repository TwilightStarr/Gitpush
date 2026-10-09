export interface Repo {
  id: number;
  name: string;
  fullName: string;
  owner: string;
  isPrivate: boolean;
  defaultBranch: string;
  description: string | null;
  htmlUrl: string;
  updatedAt: string;
}

export interface Branch {
  name: string;
  sha: string;
}

export interface GitFile {
  path: string;
  name: string;
  content: Uint8Array;
  size: number;
  isText: boolean;
}

export interface RepoContentItem {
  name: string;
  path: string;
  type: 'file' | 'dir';
  size: number;
  sha: string;
}

export interface ActionRun {
  id: number;
  name: string;
  status: string;
  conclusion: string | null;
  event: string;
  createdAt: string;
  htmlUrl: string;
}

export interface PushProgress {
  progress: number; // 0 to 1
  message: string;
  step: 'init' | 'blobs' | 'tree' | 'commit' | 'ref' | 'done' | 'error';
}

export type ActiveTab = 'zip' | 'multi' | 'repos' | 'actions' | 'flutter_code';
