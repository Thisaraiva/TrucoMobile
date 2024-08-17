import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:truco_mobile/src/config/error_message.dart';
import 'package:truco_mobile/src/model/card_model.dart';
import 'package:truco_mobile/src/model/player_model.dart';
import 'package:truco_mobile/src/widget/custom_toast.dart';

class GameDatabaseManager {
  CollectionReference games = FirebaseFirestore.instance.collection('games');

  Future<void> createTrucoGame(String gameName, bool gameType, int totalPlayers, Map<String, dynamic> deck) async {
    try {
      await games.add({
        'name': gameName,
        'isPaulista': gameType,
        'totalPlayers': totalPlayers,
        'createdAt': FieldValue.serverTimestamp(),
        'deck': deck,
        'players': []
      });
      genericToast(gameCreateSucessuful, Colors.green, Colors.white);
    } catch (e) {
      genericToast(gameCreateError, Colors.red, Colors.white);
      debugPrint('Erro ao criar a partida: $e');
    }
  }

  Future<List<CardModel>> getGameCards(String gameId) async {
    try {
      DocumentSnapshot gameDoc = await games.doc(gameId).get();
      if (gameDoc.exists && gameDoc.data() != null) {
        var data = gameDoc.data() as Map<String, dynamic>;
        var deck = data['deck'];
        if (deck != null && deck['cards'] != null) {
          var cards = (deck['cards'] as List)
              .map((item) => CardModel.fromMap(item))
              .toList();
          return cards;
        } else {
          print('Não foram encontradas cards no deck.');
        }
      } else {
        print('Documento do jogo não encontrado.');
      }
    } catch (e) {
      genericToast('Houve um erro ao buscar o documento $e', Colors.red, Colors.white);
      debugPrint('Houve um erro ao buscar o documento: $e');
    }
    return [];
  }

  Future<void> joinGame(String gameId, PlayerModel player) async {
    try {
      await games.doc(gameId).update({'players': FieldValue.arrayUnion([player.toMap()])});
      genericToast('Jogador ${player.name} entrou na partida', Colors.green, Colors.white);
    } catch (e) {
      genericToast('Houve um erro ao entrar na partida $e', Colors.red, Colors.white);
      debugPrint('Erro ao entrar na partida: $e');
    }
  }

  Future<void> updateGameCards(String gameId, List<dynamic> cards) async {
    try {
      await games.doc(gameId).update({'deck.cards': cards});
    } catch (e) {
      genericToast('Erro ao atualizar as cartas do jogo', Colors.red, Colors.white);
      debugPrint('Erro ao atualizar as cartas do jogo: $e');
    }
  }
  
  Future<List<Map<String, dynamic>>> fetchGameRooms() async {
    QuerySnapshot querySnapshot = await games.get();
    final allData = querySnapshot.docs
        .map((doc) => ({...doc.data() as Map<String, dynamic>, 'id': doc.id}))
        .toList();
    return allData;
  }

  Future<void> deleteGameRoom(String id) async {
    await games.doc(id).delete();
  }
}
