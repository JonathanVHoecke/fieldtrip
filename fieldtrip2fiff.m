function fieldtrip2fiff(filename, data, varargin)

% FIELDTRIP2FIFF saves a FieldTrip raw data structure as a fiff-file, allowing it
% to be further analyzed by the Neuromag/Elekta/Megin software, or in MNE-python.
%
% Use as
%   fieldtrip2fiff(filename, data)
% where filename is the name of the output file, and data is a raw data structure
% as obtained from FT_PREPROCESSING, or a timelock structure obtained from
% FT_TIMELOCKANALYSIS.
%
% Additional options can be specified as key-value pairs:
%   precision = string ('single'/'double'), determines the precision with which
%                 the numeric data is written to file, default is the class of the
%                 numeric data
% 
% If the data comes from preprocessing and has only one trial, then it writes the
% data into raw continuous format. 
% 
% If present in the data, the original header is reused (also removing the non-used channels).
% Otherwise, the function attempts to create the header, which might or might not be correct
% (e.g. with respect to the scaling and the sensor locations. 
% 
% If the data contains events in the cfg structure, it writes the events in the MNE format
% (three columns) into a file based on "filename", ending with "-eve.fif". If only a subset
% of the events is to be written to the event file, one can use the additional key-value pair:
%   eventtype = string (or cell array of string) with the eventtypes to be
%                 written to file, default 'all'
% 
% See also FT_DATATYPE_RAW, FT_DATATYPE_TIMELOCK

% Copyright (C) 2012-2013, Jan-Mathijs Schoffelen, Gio Piantoni
% Copyright (C) 2023, Jan-Mathijs Schoffelen
%
% This file is part of FieldTrip, see http://www.fieldtriptoolbox.org
% for the documentation and details.
%
%    FieldTrip is free software: you can redistribute it and/or modify
%    it under the terms of the GNU General Public License as published by
%    the Free Software Foundation, either version 3 of the License, or
%    (at your option) any later version.
%
%    FieldTrip is distributed in the hope that it will be useful,
%    but WITHOUT ANY WARRANTY; without even the implied warranty of
%    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
%    GNU General Public License for more details.
%
%    You should have received a copy of the GNU General Public License
%    along with FieldTrip. If not, see <http://www.gnu.org/licenses/>.
%
% $Id$

% this ensures that the path is correct and that the ft_defaults global variable is available
ft_defaults

% ensure that the filename has the correct extension
[pathstr, name, ext] = fileparts(filename);
if ~strcmp(ext, '.fif')
  ft_error('If the filename is specified with a file extension, this should read .fif');
end
fifffile  = fullfile(pathstr ,[name '.fif']);
eventfile = fullfile(pathstr ,[name '-eve.fif']);

% ensure the mne-toolbox to be on the path
ft_hastoolbox('mne', 1);
FIFF = fiff_define_constants; % some constants are not defined in the MATLAB function

% check if the input data is valid for this function
data   = ft_checkdata(data, 'datatype', {'raw', 'timelock'}, 'hassampleinfo', 'yes', 'feedback', 'yes');
istlck = ft_datatype(data, 'timelock') && isfield(data, 'avg');
israw  = ft_datatype(data, 'raw') && numel(data.trial)==1;
isepch = ft_datatype(data, 'timelock') || (ft_datatype(data, 'raw') && numel(data.trial)>1);
if isepch
  data = ft_checkdata(data, 'datatype', 'timelock', 'feedback', 'yes');
end
if israw
  fsample = 1./mean(diff(data.time{1}));
  dtype   = class(data.trial{1});
  iscomplex = ~isreal(data.trial{1});
else
  fsample = 1./mean(diff(data.time));
  if isfield(data, 'trial')
    dtype   = class(data.trial);
    iscomplex = ~isreal(data.trial);
  elseif isfield(data, 'avg')
    dtype = class(data.avg);
    iscomplex = ~isreal(data.avg);
  end
end
precision = ft_getopt(varargin, 'precision', dtype);
if ~ismember(precision, {'single' 'double'})
  % FIXME consider casting non single/double data to the supported class
  ft_error('only single or double precision data is supported');
end

% Create a fiff-header, or take information from the original header if possible
if isfield(data, 'hdr') && isfield(data.hdr, 'orig') && isfield(data.hdr.orig, 'meas_id')
  ft_notice('The data contains header information that seems to be derived from a FIFF file,\nre-using header information, channel locations may be read \nfrom .grad and .elec in the data');
  info = data.hdr.orig;
else
  info.meas_id.version = NaN;
  info.meas_id.machid  = [NaN;NaN];
  info.meas_id.secs    = NaN;
  info.meas_id.usecs   = NaN;
  info.meas_date       = [NaN;NaN];
  info.acq_pars        = []; % needed by raw
  info.acq_stim        = []; % needed by raw
  info.highpass        = NaN;
  info.lowpass         = NaN;
  
  % these are not strictly necessary, but the inverse functions in MNE works better if this matrix is present
  info.dev_head_t.from  = 1;
  info.dev_head_t.to    = 4;
  info.dev_head_t.trans = eye(4); % this is of course not correct, but the exact transformation depends on the system
  
  info.ctf_head_t = [];
  info.dig        = [];
  info.projs      = struct('kind', {}, 'data', {}, 'active',  {}, 'desc', {});
  info.comps      = struct('kind', {}, 'data', {}, 'ctfkind', {}, 'save_calibrated', {}, 'rowcals', {}, 'colcals', {});
  info.bads       = [];
  
  info.isaverage    = double(istlck);
  info.isepoched    = double(isepch);
  info.iscontinuous = double(israw);
  info.sfreq        = fsample;
end

info.ch_names = data.label(:)';
info.chs      = sens2fiff(data);
info.nchan    = numel(data.label);

if iscomplex && strcmp(precision, 'single')
  dtype = FIFF.FIFFT_COMPLEX_FLOAT;
elseif iscomplex && strcmp(precision, 'double')
  dtype = FIFF.FIFFT_COMPLEX_DOUBLE;
elseif ~iscomplex && strcmp(precision, 'single')
  dtype = FIFF.FIFFT_FLOAT;
elseif ~iscomplex && strcmp(precision, 'double')
  dtype = FIFF.FIFFT_DOUBLE;
else
  ft_error('writing data in requested precision is not supported');
end

if israw
  [outfid, cals] = fiff_start_writing_raw(fifffile, info);
  fiff_write_raw_buffer(outfid, data.trial{1}, cals, dtype);
  fiff_finish_writing_raw(outfid);
  
  % write events, if they exist
  if isfield(data, 'cfg')
    event = ft_findcfg(data.cfg, 'event');
  else
    event = [];
  end
  if ~isempty(event)
    eventtype = ft_getopt(varargin, 'eventtype', 'all');
    [eventlist, mappings] = convertevent(event, eventtype);
    fiff_write_events(eventfile, eventlist, mappings);
    ft_info('Writing events to %s\n', eventfile)
  end
  
elseif istlck
  evoked.aspect_kind = 100;
  evoked.is_smsh     = 0;
  evoked.nave        = max(data.dof(:));
  evoked.first       = round(data.time(1)*info.sfreq);
  evoked.last        = round(data.time(end)*info.sfreq);
  evoked.times       = data.time;
  evoked.comment     = sprintf('exported from FieldTrip: averaged data');
  evoked.epochs      = data.avg;
  
  fiffdata.info   = info;
  fiffdata.evoked = evoked;
  fiff_write_evoked(fifffile, fiffdata,dtype);
  
elseif isepch
  nsmp   = numel(data.time);
  ntrl   = size(data.trial,1);    
  if isfield(data, 'trialinfo')
    ft_warning('Using the first column of the trialinfo field as event values');
    trg = data.trialinfo(:,1);
  else
    trg = ones(ntrl,1);
  end
  events = [((0:nsmp:(nsmp*(ntrl-1))))' zeros(ntrl,1) trg];
  vals = unique(trg);
  vals = [(1:numel(vals))' vals]';
  eventid = sprintf('event%d: %d;',vals(:));
  eventid = eventid(1:end-1); % remove the last comma

  epochs.epoch = data.trial;
  epochs.tmin  = data.time(1).*info.sfreq;
  epochs.tmax  = data.time(end).*info.sfreq;
  epochs.baseline  = [];
  epochs.selection = (1:size(data.trial,1))'-1; % seems 0-based
  epochs.drop_log  = ['[',repmat('[], ',[1 size(data.trial,1)-1]), '[]]'];
  epochs.events    = events;
  epochs.event_id  = eventid;
  epochs.comment   = 'exported from FieldTrip: epoched data';

  fiffdata.info  = info;
  fiffdata.epoch = epochs;
  fiff_write_epochs(fifffile, fiffdata, dtype);


end

%-------------------
% subfunction
function [chs] = sens2fiff(data)

if isfield(data, 'hdr') && isfield(data.hdr, 'orig') && isfield(data.hdr.orig, 'chs')
  % use orig information if available
  ft_warning('Using the original channel information from the header, this may be wrong if channels have been pruned, reordered, rescaled');
  [i_label, i_chs] = match_str(data.label, {data.hdr.orig.chs.ch_name}');
  if numel(i_label) < numel(data.label)
    ft_error('There are more channels in the data than in the original header information, this is currently not supported');
  end
  chs(i_label)     = data.hdr.orig.chs(i_chs);
else
  % otherwise reconstruct a usable channel information array
  ft_warning('Reconstructing channel information based on the available data, it might be inaccurate\n');
  FIFF = fiff_define_constants; % some constants are not defined in the MATLAB function
  
  hasgrad = isfield(data, 'grad');
  haselec = isfield(data, 'elec');
  nchan   = numel(data.label);
  
  stype = zeros(nchan, 1)-1;
  indx  = nan(nchan,1);
  
  if haselec
    [i_labeeg, i_elec] = match_str(data.label, data.elec.label);
    stype(i_labeeg) = 0; %meg/eeg/other = 1/0/-1
    indx(i_labeeg)  = i_elec; %indexes into the grad/elec
   
    data.elec = ft_convert_units(data.elec, 'm'); % this seems needed for a correct round trip
  end
  
  if hasgrad
    [i_labmeg, i_grad] = match_str(data.label, data.grad.label);
    stype(i_labmeg) = 1;
    indx(i_labmeg)  = i_grad;
  
    data.grad = ft_convert_units(data.grad, 'm');
    data.grad = undobalancing(data.grad); % if this fails, then it's difficult to write out meaningful channel info to begin with
    [coiltype, coilkind] = grad2coiltype(data.grad);
    coilunit  = grad2coilunit(data.grad, FIFF);
  end

  scanno  = num2cell((1:nchan)');
  ch_name = data.label(:);
  range   = num2cell(ones(nchan,1));
  cal     = num2cell(ones(nchan,1));

  cnt_grad = 0;
  cnt_elec = 0;
  cnt_else = 0;
  chs = struct('scanno', scanno, 'ch_name', ch_name, 'range', range, 'cal', cal)';
  for k = 1:nchan
  
    switch stype(k)
      case 1
        % MEG
        cnt_grad = cnt_grad + 1;
        
        % safety check
        selcoil = data.grad.tra(indx(k),:)~=0;
        assert(sum(selcoil)<=2);
        
        pos  = data.grad.chanpos(indx(k),:);
        ori  = data.grad.chanori(indx(k),:);
        
        R   = ori2r(ori, data.grad.coilpos(selcoil, :), coiltype(indx(k)));

        chs(1,k).logno        = cnt_grad;
        chs(1,k).kind         = coilkind(indx(k));
        chs(1,k).coil_type    = coiltype(indx(k));
        chs(1,k).unit         = coilunit(indx(k));
        chs(1,k).coil_trans   = [R pos(:); 0 0 0 1];
        chs(1,k).unit_mul     = 0;
        chs(1,k).coord_frame  = FIFF.FIFFV_COORD_HEAD;
        chs(1,k).eeg_loc      = [];
        chs(1,k).loc          = [pos(:); R(:)];
        chs(1,k).cal          = 1;

      case 0
        % EEG
        cnt_elec = cnt_elec + 1;
       
        chs(1,k).logno        = cnt_elec;
        chs(1,k).kind         = FIFF.FIFFV_EEG_CH;
        chs(1,k).coil_type    = NaN;
        chs(1,k).coil_trans   = [];
        chs(1,k).unit         = FIFF.FIFF_UNIT_V;
        chs(1,k).unit_mul     = log10(ft_scalingfactor(data.elec.chanunit{indx(k)}, 'V')); 
        chs(1,k).coord_frame  = FIFF.FIFFV_COORD_DEVICE;
        chs(1,k).eeg_loc      = [data.elec.chanpos(indx(k),:)' zeros(3,1)];
        chs(1,k).loc          = [chs(1,k).eeg_loc(:); 0; 1; 0; 0; 0; 1];
        chs(1,k).cal          = 1;

      case -1
        % OTHER
        cnt_else = cnt_else + 1;
        
        chs(1,k).logno        = cnt_else;
        chs(1,k).kind         = NaN;
        chs(1,k).coil_type    = NaN;
        chs(1,k).coil_trans   = [];
        chs(1,k).unit         = NaN;
        chs(1,k).unit_mul     = 0;
        chs(1,k).coord_frame  = NaN;
        chs(1,k).eeg_loc      = [];
        chs(1,k).loc          = zeros(12,1);
        chs(1,k).cal          = 1;

      otherwise
    end

  end
end


function [eventlist, mappings] = convertevent(event, eventtype)

ev_type  = {event.type};
ev_utype = unique(ev_type);
ft_info('Detected %d events, of %d different event types\n', numel(ev_type), numel(ev_utype));

if isequal(eventtype, 'all')
  ft_info('Writing all event types\n');
else
  if ischar(eventtype)
    eventtype = {eventtype};
  end
  ev_utype = intersect(ev_utype, eventtype);
  ft_info('Writing a selection of event types\n');
end

% a specific event type, can have different numeric (or non-numeric
% values), or can have an empty value
cnt = 0;
for k = 1:numel(ev_utype)
  sel = strcmp(ev_type, ev_utype{k});
  if isempty([event(sel).value])
    ft_info('Event type %s: %d occurrences\n', ev_utype{k}, sum(sel));
    cnt = cnt+1;
    ev(cnt).id     = ev_utype{k};
    ev(cnt).sample = [event(sel).sample];
  else
    val = {event(sel).value};
    if all(cellfun(@isnumeric, val))
      val = [event(sel).value];
      smp = [event(sel).sample];
      uval = unique(val);
      for kk = 1:numel(uval)
        cnt = cnt+1;
        ev(cnt).id     = sprintf('%s_%d', ev_utype{k}, uval(kk));
        ev(cnt).sample = smp(val==uval(kk));
        ft_info('Event type %s with value %d: %d occurrences\n', ev_utype{k}, uval(kk), sum(val==uval(kk)));
      end
    else
      uval = unique(val);
      for kk = 1:numel(uval)
        cnt = cnt+1;
        ev(cnt).id     = sprintf('%s_%s', ev_utype{k}, uval{kk});
        ev(cnt).sample = smp(strcmp(val, uval{kk}));
        ft_info('Event type %s with value %s: %d occurrences\n', ev_utype{k}, uval{kk}, sum(val==uval(kk)));
      end
    end
  end
end

mappings  = '';
eventlist = zeros(0,3);
for k = 1:numel(ev)
  mappings  = sprintf('%s, %s:%d', mappings, ev(k).id, k);

  smp = ev(k).sample(:)-1; % in the fiff-file the samples are 0 based
  eventlist = cat(1, eventlist, [smp zeros(numel(smp),1) ones(numel(smp),1).*k]); 
end
[srt, ix] = sort(eventlist(:,1));
eventlist = eventlist(ix,:);
mappings  = mappings(3:end);

function [coiltype, coilkind] = grad2coiltype(grad)

stype = ft_senstype(grad);
def   = mne_load_coil_def('coil_def.dat');
def   = def([def.accuracy]==0);
descr = {def.description}';

coiltype = nan(numel(grad.label), 1);
coilkind = nan(numel(grad.label), 1);
ctype    = grad.chantype;
switch stype
  case 'neuromag122'
    % this can in theory happen, but is not supported yet, FIXME please
    % feel free to add support for this (and the below) when you need it.
    ft_warning('deteced neuromag122 as sensory array, but no original channel info will be used')
  case 'neuromag306'
    ft_warning('deteced neuromag306 as sensory array, but no original channel info will be used')
 
  case {'ctf151' 'ctf275'}
    
    % the MEG gradiometers, hardcoded id from fif definition
    coiltype(strcmp(ctype, 'meggrad')) = 5001;
    coilkind(strcmp(ctype, 'meggrad')) = 1;

    % the REF magnetometers, hardcoded id from fif definition
    coiltype(strcmp(ctype, 'refmag')) = 5002;
    coilkind(strcmp(ctype, 'refmag')) = 301;

    % the REF gradiometers, hardcoded id from fif definition
    coiltype(~isfinite(coiltype)&strcmp(ctype, 'refgrad')&contains(grad.label,'11')) = 5003;
    coiltype(~isfinite(coiltype)&strcmp(ctype, 'refgrad')&contains(grad.label,'22')) = 5003;
    coiltype(~isfinite(coiltype)&strcmp(ctype, 'refgrad')&contains(grad.label,'33')) = 5003;
    coiltype(~isfinite(coiltype)&strcmp(ctype, 'refgrad'))                           = 5004;
    coilkind(strcmp(ctype, 'refgrad')) = 301;

  case 'bti148'
    % hardcoded id from fif definition
    coiltype(strcmp(ctype, 'megmag')) = 4001;
    coilkind(strcmp(ctype, 'megmag')) = 1;
    coiltype(strcmp(ctype, 'refmag')) = 4003;
    coilkind(strcmp(ctype, 'refmag')) = 301;  
    coiltype(strcmp(ctype, 'refgrad')&contains(grad.label,'xx')) = 4004;
    coiltype(strcmp(ctype, 'refgrad')&contains(grad.label,'yy')) = 4004;
    coiltype(strcmp(ctype, 'refgrad')&contains(grad.label,'zz')) = 4004;
    coiltype(strcmp(ctype, 'refgrad')&~isfinite(coiltype)) = 4005;
    coilkind(strcmp(ctype, 'refgrad')) = 301;

  case 'bti248'
    % hardcoded id from fif definition
    coiltype(strcmp(ctype, 'megmag')) = 4001;
    coilkind(strcmp(ctype, 'megmag')) = 1;
    coiltype(strcmp(ctype, 'refmag')) = 4003;
    coilkind(strcmp(ctype, 'refmag')) = 301;  
    coiltype(strcmp(ctype, 'refgrad')&contains(grad.label,'xx')) = 4004;
    coiltype(strcmp(ctype, 'refgrad')&contains(grad.label,'yy')) = 4004;
    coiltype(strcmp(ctype, 'refgrad')&~isfinite(coiltype)) = 4005;
    coilkind(strcmp(ctype, 'refgrad')) = 301;

  case 'bti248grad'
    % hardcoded id from fif definition
    coiltype(strcmp(ctype, 'meggrad')) = 4002;
    coilkind(strcmp(ctype, 'meggrad')) = 1;
    coiltype(strcmp(ctype, 'refmag'))  = 4003;
    coilkind(strcmp(ctype, 'refmag'))  = 301;  
    coiltype(strcmp(ctype, 'refgrad')&contains(grad.label,'xx')) = 4004;
    coiltype(strcmp(ctype, 'refgrad')&contains(grad.label,'yy')) = 4004;
    coiltype(strcmp(ctype, 'refgrad')&~isfinite(coiltype)) = 4005;
    coilkind(strcmp(ctype, 'refgrad')) = 301;

  otherwise
    stype = 'point magnetometer';
    % treat as point magnetometer system
    sel         = strcmp(descr, 'Point magnetometer');
    coiltype(:) = def(sel).id; 
end

% this is needed as long as neuromag is not properly dealt with in the above
if all(~isfinite(coiltype))
  stype = 'point magnetometer';
  % treat as point magnetometer system
  sel         = strcmp(descr, 'Point magnetometer');
  coiltype(:) = def(sel).id; 
end
ft_info('creating coiltypes according to sensor type: %s', stype);


function coilunit = grad2coilunit(grad, FIFF)

coilunit = zeros(numel(grad.label),1)-1;
for k = 1:numel(grad.chanunit)
  switch grad.chanunit{k}
    case 'T'
      coilunit(k) = FIFF.FIFF_UNIT_T;
    case 'T/m'
      coilunit(k) = FIFF.FIFF_UNIT_T_M;
    otherwise
      % figure out what to do if T/cm or so -> I think that this goes into
      % the unit_mul field
  end
end

function [ex, ey] = plane_unitvectors(ez)

% subfunction to obtain a pair of vectors that span the plane orthogonal to
% ez. The heuristic is inspired by the MNE-python code

if abs(abs(ez(3))-1)<1e-5
  ex = [1 0 0]';
else
  ex = zeros(3,1);
  if ez(2)<ez(3)
    if ez(1)<ez(2)
      ex(1) = 1;
    else
      ex(2) = 1;
    end
  else
    if ez(1)<ez(2)
      ex(1) = 1;
    else
      ex(3) = 1;
    end
  end
end
ex = ex - (ex'*ez).*ez;
ex = ex / norm(ex);
ey = cross(ez, ex);

function R = ori2r(ori, pos, coiltype)

% helper function to get the orthonormal matrix that describes the local
% coordinate system of a sensor in fif convention. Note that not all
% coiltypes are guaranteed to be correct

switch coiltype
  case 5004
    % off diagonal CTF reference gradiometer
    ex  = pos'*[1;-1]; % line between the coils
    ex  = ex./norm(ex);
    ez  = ori(:);
    ey  = cross(ez,ex);
  case 4005
    % off diagonal Magnes reference gradiometer
    ex  = pos'*[1;-1]; % line between the coils
    ex  = ex./norm(ex);
    ez  = ori(:);
    ey  = cross(ez,ex);
  otherwise
    ez       = ori(:);
    [ex, ey] = plane_unitvectors(ez);
end
R        = [ex(:) ey(:) ez(:)];

