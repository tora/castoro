/*
 *   Copyright 2010 Ricoh Company, Ltd.
 *
 *   This file is part of Castoro.
 *
 *   Castoro is free software: you can redistribute it and/or modify
 *   it under the terms of the GNU Lesser General Public License as published by
 *   the Free Software Foundation, either version 3 of the License, or
 *   (at your option) any later version.
 *
 *   Castoro is distributed in the hope that it will be useful,
 *   but WITHOUT ANY WARRANTY; without even the implied warranty of
 *   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *   GNU Lesser General Public License for more details.
 *
 *   You should have received a copy of the GNU Lesser General Public License
 *   along with Castoro.  If not, see <http://www.gnu.org/licenses/>.
 *
 */

#ifndef __INCLUDE_GATEWAY_BASETYPES_H__
#define __INCLUDE_GATEWAY_BASETYPES_H__

#include <vector>
#include <list>
#include <map>
#include <sys/time.h>

# include <ruby.h>

#include "basket.hxx"

#define CACHEPAGE_SIZE  (4096ull)    // Must be 2^n
#define attr_reader(type, member) inline type member##_r() { return member; }
#define attr_reader_ref(type, member) inline type* member##_r() { return &member; }

namespace Castoro {
namespace Gateway {

  // for Result of Database#find(require_space).
  typedef std::vector<ID> ArrayOfId;


  // for Result of Database#find(content_id, type, revision).
  typedef struct {
    ID  peer;       // Peer name by ID(ruby).
    ID  base;       // Peer base_dir by ID(ruby).
  } PeerWithBase;
  typedef std::vector<PeerWithBase> ArrayOfPeerWithBase;


  // for Database#set_status().
  typedef enum {
    DS_UNKNOWN   = 0,
    DS_MAINTENANCE = 10,
    DS_READONLY = 20,
    DS_ACTIVE = 30
  } DetailStatus;


  // { content_id, type } pair for Database.
  class ContentIdWithType {
  public:
    inline ContentIdWithType(const BasketId& id=0ull, uint32_t t=0) {
      BasketId tmp = CACHEPAGE_SIZE-1ull;
      basket_id = id & (~tmp);
      type = t;
    };
    inline ~ContentIdWithType() {}; // NOT virtual.
    inline bool operator<(const ContentIdWithType& y) const {
      if(type==y.type)  return (basket_id < y.basket_id);
      return (type < y.type);
    };
    inline bool operator==(const ContentIdWithType& y) const {
      if(type==y.type)  return (basket_id == y.basket_id);
      return (type == y.type);
    };

  public:
    BasketId  basket_id;
    uint32_t  type;
  };


  // { peer, type } pair for Database.
  class PeerIdWithType {
  public:
    inline PeerIdWithType(ID p=0, uint32_t t=0) {
      peer = p;
      type = t;
    };
    inline ~PeerIdWithType() {}; // NOT vertual.
    inline bool operator<(const PeerIdWithType& y) const {
      if(type==y.type)  return (peer < y.peer);
      return (type < y.type);
    };
    inline bool operator==(const PeerIdWithType& y) const {
      if(type==y.type)  return (peer == y.peer);
      return (type == y.type);
    };

  public:
    ID        peer;
    uint32_t  type;
  };


}
}


#endif //__INCLUDE_GATEWAY_BASETYPES_H__
