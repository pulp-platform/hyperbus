## Manuel Eggimann <meggimann@iis.ee.ethz.ch>
##
## Copyright (C) 2021-2022 ETH Zürich
## 
## Licensed under the Apache License, Version 2.0 (the "License");
## you may not use this file except in compliance with the License.
## You may obtain a copy of the License at
##
##     http://www.apache.org/licenses/LICENSE-2.0
##
## Unless required by applicable law or agreed to in writing, software
## distributed under the License is distributed on an "AS IS" BASIS,
## WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
## See the License for the specific language governing permissions and
## limitations under the License.
// Copyright 2026 Fondazione Chips-IT.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

% for line in header_text.splitlines():
// ${line}
% endfor
package pkg_${padframe.name};

% for pad_domain in padframe.pad_domains:
  //Structs for ${pad_domain.name}

% if pad_domain.override_signals:
  //Override signals
  typedef struct packed {
% for signal in pad_domain.override_signals:
     logic ${f"[{signal.size-1}:0]" if signal.size > 1 else ""} ${signal.name};
% endfor
  } pad_domain_${pad_domain.name}_override_signals_t;

% endif
% if pad_domain.static_connection_signals:
  //Static connections signals
% if pad_domain.static_connection_signals_soc2pad:
   typedef struct packed {
% for signal in pad_domain.static_connection_signals_soc2pad:
      logic       ${f"[{signal.size-1}:0]" if signal.size > 1 else ""} ${signal.name};
% endfor
     } pad_domain_${pad_domain.name}_static_connection_signals_soc2pad_t;

% endif
% if pad_domain.static_connection_signals_pad2soc:
   typedef struct packed {
% for signal in pad_domain.static_connection_signals_pad2soc:
      logic       ${f"[{signal.size-1}:0]" if signal.size > 1 else ""} ${signal.name};
% endfor
     } pad_domain_${pad_domain.name}_static_connection_signals_pad2soc_t;

% endif
% endif
% if pad_domain.port_groups:
  // Port Group signals
% for port_group in pad_domain.port_groups:
% if port_group.port_signals_soc2pads:
   typedef struct packed {
% for signal in port_group.port_signals_soc2pads:
      logic       ${f"[{signal.size-1}:0]" if signal.size > 1 else ""} ${signal.name};
% endfor
     } pad_domain_${pad_domain.name}_port_group_${port_group.name}_soc2pad_t;

% endif
% if port_group.port_signals_pads2soc:
   typedef struct packed {
% for signal in port_group.port_signals_pads2soc:
      logic       ${f"[{signal.size-1}:0]" if signal.size > 1 else ""} ${signal.name};
% endfor
     } pad_domain_${pad_domain.name}_port_group_${port_group.name}_pad2soc_t;

% endif
% endfor
% if any([port_group.port_signals_soc2pads for port_group in pad_domain.port_groups]):
   typedef struct packed {
% for port_group in pad_domain.port_groups:
% if port_group.port_signals_soc2pads:
     pad_domain_${pad_domain.name}_port_group_${port_group.name}_soc2pad_t ${port_group.name};
% endif
% endfor
     } pad_domain_${pad_domain.name}_ports_soc2pad_t;

% endif
% if any([port_group.port_signals_pads2soc for port_group in pad_domain.port_groups]):
   typedef struct packed {
% for port_group in pad_domain.port_groups:
% if port_group.port_signals_pads2soc:
     pad_domain_${pad_domain.name}_port_group_${port_group.name}_pad2soc_t ${port_group.name};
% endif
% endfor
     } pad_domain_${pad_domain.name}_ports_pad2soc_t;

% endif
% endif
% endfor

  //Toplevel structs

% if any([pad_domain.override_signals for pad_domain in padframe.pad_domains]):
  typedef struct packed{
% for pad_domain in padframe.pad_domains:
    pad_domain_${pad_domain.name}_override_signals_t ${pad_domain.name};
% endfor
  } override_signals_t;

% endif
% if any([pad_domain.static_connection_signals_pad2soc for pad_domain in padframe.pad_domains]):
  typedef struct packed {
% for pad_domain in padframe.pad_domains:
% if pad_domain.static_connection_signals_pad2soc:
    pad_domain_${pad_domain.name}_static_connection_signals_pad2soc_t ${pad_domain.name};
% endif
% endfor
  } static_connection_signals_pad2soc_t;

% endif
% if any([pad_domain.static_connection_signals_soc2pad for pad_domain in padframe.pad_domains]):
  typedef struct packed {
% for pad_domain in padframe.pad_domains:
% if pad_domain.static_connection_signals_soc2pad:
    pad_domain_${pad_domain.name}_static_connection_signals_soc2pad_t ${pad_domain.name};
% endif
% endfor
  } static_connection_signals_soc2pad_t;

% endif
% if any([port_group.port_signals_pads2soc for port_group in pad_domain.port_groups for pad_domain in padframe.pad_domains]):
  typedef struct packed {
% for pad_domain in padframe.pad_domains:
% if any(port_group.port_signals_pads2soc for port_group in pad_domain.port_groups):
    pad_domain_${pad_domain.name}_ports_pad2soc_t ${pad_domain.name};
% endif
% endfor
  } port_signals_pad2soc_t;

% endif
% if any([port_group.port_signals_soc2pads for port_group in pad_domain.port_groups for pad_domain in padframe.pad_domains]):
  typedef struct packed {
% for pad_domain in padframe.pad_domains:
% if any(port_group.port_signals_soc2pads for port_group in pad_domain.port_groups):
    pad_domain_${pad_domain.name}_ports_soc2pad_t ${pad_domain.name};
% endif
% endfor
  } port_signals_soc2pad_t;
% endif


endpackage : pkg_${padframe.name}
